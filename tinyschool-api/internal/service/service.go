package service

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"tinyschool-api/internal/backup"
	"tinyschool-api/internal/dto"
	"tinyschool-api/internal/model"
	"tinyschool-api/internal/storage"
)

var (
	ErrValidation   = errors.New("validation failed")
	ErrNotFound     = errors.New("not found")
	ErrConflict     = errors.New("conflict")
	ErrUnauthorized = errors.New("unauthorized")
)

type Error struct {
	Kind    error
	Message string
	Err     error
}

func (e *Error) Error() string {
	return e.Message
}

func (e *Error) Unwrap() error {
	if e.Err != nil {
		return errors.Join(e.Kind, e.Err)
	}
	return e.Kind
}

type App struct {
	storage            storage.Storage
	now                func() time.Time
	id                 func(string) (string, error)
	sessionDuration    time.Duration
	tokenDuration      time.Duration
	resetTokenDuration time.Duration
	appBaseURL         string
	jwtSecret          []byte
	logger             *slog.Logger
	backups            *backup.Manager
}

type Option func(*App)

func WithClock(now func() time.Time) Option {
	return func(app *App) { app.now = now }
}

func WithIDGenerator(generate func(string) (string, error)) Option {
	return func(app *App) { app.id = generate }
}

func WithSessionDuration(duration time.Duration) Option {
	return func(app *App) {
		if duration > 0 {
			app.sessionDuration = duration
		}
	}
}

func WithTokenDuration(duration time.Duration) Option {
	return func(app *App) {
		if duration > 0 {
			app.tokenDuration = duration
		}
	}
}

func WithJWTSecret(secret []byte) Option {
	return func(app *App) {
		if len(secret) > 0 {
			app.jwtSecret = append([]byte(nil), secret...)
		}
	}
}

// WithAppBaseURL sets the origin used to build links sent to users, such as
// password reset links.
func WithAppBaseURL(baseURL string) Option {
	return func(app *App) {
		if trimmed := strings.TrimRight(strings.TrimSpace(baseURL), "/"); trimmed != "" {
			app.appBaseURL = trimmed
		}
	}
}

func WithResetTokenDuration(duration time.Duration) Option {
	return func(app *App) {
		if duration > 0 {
			app.resetTokenDuration = duration
		}
	}
}

func WithLogger(logger *slog.Logger) Option {
	return func(app *App) {
		if logger != nil {
			app.logger = logger
		}
	}
}

func WithBackups(manager *backup.Manager) Option {
	return func(app *App) { app.backups = manager }
}

func New(store storage.Storage, options ...Option) *App {
	secret := make([]byte, 32)
	_, _ = rand.Read(secret)
	app := &App{
		storage:            store,
		now:                time.Now,
		id:                 randomID,
		sessionDuration:    24 * time.Hour,
		tokenDuration:      15 * time.Minute,
		resetTokenDuration: time.Hour,
		appBaseURL:         "http://localhost:8080",
		jwtSecret:          secret,
		logger:             slog.Default(),
	}
	for _, option := range options {
		option(app)
	}
	return app
}

func (a *App) Ping(ctx context.Context) error {
	return a.storage.Ping(ctx)
}

func randomID(prefix string) (string, error) {
	bytes := make([]byte, 8)
	if _, err := rand.Read(bytes); err != nil {
		return "", fmt.Errorf("generate %s id: %w", prefix, err)
	}
	return prefix + "_" + hex.EncodeToString(bytes), nil
}

func (a *App) newID(prefix string) (string, error) {
	id, err := a.id(prefix)
	if err != nil {
		return "", &Error{Kind: err, Message: "could not generate an id", Err: err}
	}
	return id, nil
}

func validation(message string) error {
	return &Error{Kind: ErrValidation, Message: message}
}

func unauthorized(message string) error {
	return &Error{Kind: ErrUnauthorized, Message: message}
}

func conflict(message string) error {
	return &Error{Kind: ErrConflict, Message: message}
}

func translate(err error, resource string) error {
	switch {
	case err == nil:
		return nil
	case errors.Is(err, storage.ErrNotFound):
		return &Error{Kind: ErrNotFound, Message: resource + " not found", Err: err}
	case errors.Is(err, storage.ErrConflict):
		return &Error{Kind: ErrConflict, Message: resource + " conflicts with existing data", Err: err}
	default:
		return err
	}
}

func listOptions(input dto.ListOptions, allowed map[string]bool, defaultSort string) (storage.ListOptions, error) {
	input.Search = strings.TrimSpace(input.Search)
	input.Sort = strings.TrimSpace(input.Sort)
	input.Order = strings.ToLower(strings.TrimSpace(input.Order))
	if input.Sort == "" {
		input.Sort = defaultSort
	}
	if !allowed[input.Sort] {
		return storage.ListOptions{}, validation("invalid sort field")
	}
	if input.Order == "" {
		input.Order = "asc"
	}
	if input.Order != "asc" && input.Order != "desc" {
		return storage.ListOptions{}, validation("order must be asc or desc")
	}
	if input.Page == 0 {
		input.Page = 1
	}
	if input.PageSize == 0 {
		input.PageSize = 10
	}
	if input.Page < 1 {
		return storage.ListOptions{}, validation("page must be positive")
	}
	if input.PageSize < 1 || input.PageSize > 100 {
		return storage.ListOptions{}, validation("pageSize must be between 1 and 100")
	}
	return storage.ListOptions{
		Search: input.Search, Sort: input.Sort, Order: input.Order,
		AcademicYearID: strings.TrimSpace(input.AcademicYearID),
		Classroom:      strings.TrimSpace(input.Classroom),
		Page:           input.Page, PageSize: input.PageSize,
	}, nil
}

func uniqueTrimmed(values []string, field string) ([]string, error) {
	result := make([]string, 0, len(values))
	seen := make(map[string]struct{}, len(values))
	for _, value := range values {
		value = strings.TrimSpace(value)
		if value == "" {
			return nil, validation(field + " cannot contain empty values")
		}
		key := strings.ToLower(value)
		if _, exists := seen[key]; exists {
			return nil, validation(field + " must contain unique values")
		}
		seen[key] = struct{}{}
		result = append(result, value)
	}
	return result, nil
}

func date(value, field string) (time.Time, error) {
	parsed, err := time.Parse(time.DateOnly, strings.TrimSpace(value))
	if err != nil {
		return time.Time{}, validation(field + " must use YYYY-MM-DD")
	}
	return parsed, nil
}

func (a *App) academicYearForDate(ctx context.Context, schoolID string, value time.Time) (model.AcademicYear, error) {
	years, _, err := a.storage.ListAcademicYears(ctx, storage.ListOptions{Sort: "startDate", Order: "asc", Page: 1, PageSize: 100})
	if err != nil {
		return model.AcademicYear{}, err
	}
	day := value.Format(time.DateOnly)
	for _, year := range years {
		if year.SchoolID == schoolID && year.StartDate <= day && day <= year.EndDate {
			return year, nil
		}
	}
	return model.AcademicYear{}, validation("date must fall within an academic year for the selected school")
}

func (a *App) applyAcademicYearDates(ctx context.Context, options *storage.ListOptions) error {
	if options.AcademicYearID == "" {
		return nil
	}
	year, err := a.storage.AcademicYear(ctx, options.AcademicYearID)
	if err != nil {
		return translate(err, "academic year")
	}
	options.DateFrom = year.StartDate
	options.DateTo = year.EndDate
	return nil
}

func percent(part, total int) int {
	if total == 0 {
		return 0
	}
	return int(float64(part)/float64(total)*100 + 0.5)
}
