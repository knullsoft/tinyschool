package httpdelivery

import (
	"context"
	"log/slog"
	"net/http"
	"strings"

	"tinyschool-api/internal/dto"
	"tinyschool-api/internal/service"
	"tinyschool-api/internal/staticui"
	"tinyschool-api/internal/tenancy"
)

const sessionCookieName = "tinyschool_session"

type Handler struct {
	app    *service.App
	logger *slog.Logger
}

func NewHandler(app *service.App, logger *slog.Logger) http.Handler {
	handler := &Handler{app: app, logger: logger}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", handler.health)
	mux.HandleFunc("GET /ready", handler.ready)
	mux.HandleFunc("POST /api/v1/auth/register", handler.register)
	mux.HandleFunc("POST /api/v1/auth/login", handler.login)
	mux.HandleFunc("POST /api/v1/auth/refresh", handler.refresh)
	mux.HandleFunc("POST /api/v1/auth/logout", handler.logout)
	mux.HandleFunc("POST /api/v1/auth/forgot-password", handler.forgotPassword)
	mux.HandleFunc("POST /api/v1/auth/reset-password", handler.resetPassword)
	handler.registerAdminRoutes(mux)

	protected := http.NewServeMux()
	handler.registerProtectedRoutes(protected)
	mux.Handle("/api/v1/", handler.authenticate(protected))
	// SPA catch-all after API and probe routes so /api/v1, /health, /ready win.
	mux.Handle("/", staticui.Handler())
	return recoverer(logger, cors(mux))
}

func (h *Handler) health(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (h *Handler) ready(w http.ResponseWriter, r *http.Request) {
	if err := h.app.Ping(r.Context()); err != nil {
		h.logger.Warn("readiness check failed", "error", err)
		writeError(w, http.StatusServiceUnavailable, "not_ready", "service is not ready")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

type identity struct {
	UserID    string
	SessionID string
}

type identityContextKey struct{}

func (h *Handler) authenticate(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		token := requestToken(r)
		user, err := h.app.Authenticate(r.Context(), token)
		if err != nil {
			writeServiceError(h.logger, w, r, err)
			return
		}
		sessionID, err := h.app.SessionID(token, false)
		if err != nil {
			writeServiceError(h.logger, w, r, err)
			return
		}
		ctx := context.WithValue(r.Context(), identityContextKey{}, identity{
			UserID: user.ID, SessionID: sessionID,
		})
		ctx = tenancy.WithUserID(ctx, user.ID)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func requestIdentity(r *http.Request) identity {
	value, _ := r.Context().Value(identityContextKey{}).(identity)
	return value
}

func requestToken(r *http.Request) string {
	const bearerPrefix = "Bearer "
	authorization := strings.TrimSpace(r.Header.Get("Authorization"))
	if len(authorization) >= len(bearerPrefix) && strings.EqualFold(authorization[:len(bearerPrefix)], bearerPrefix) {
		return strings.TrimSpace(authorization[len(bearerPrefix):])
	}
	cookie, err := r.Cookie(sessionCookieName)
	if err != nil {
		return ""
	}
	return cookie.Value
}

func decodeBody[T any](w http.ResponseWriter, r *http.Request) (T, bool) {
	var value T
	if err := decodeJSON(w, r, &value); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_json", err.Error())
		return value, false
	}
	return value, true
}

func readListOptions(w http.ResponseWriter, r *http.Request) (dto.ListOptions, bool) {
	options, err := listOptions(r)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid_query", err.Error())
		return dto.ListOptions{}, false
	}
	return options, true
}
