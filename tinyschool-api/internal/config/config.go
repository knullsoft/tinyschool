package config

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

const (
	defaultAddress         = ":8080"
	defaultDatabasePath    = "tinyschool.db"
	defaultShutdownTimeout = 10 * time.Second
	defaultSessionDuration = 24 * time.Hour
	defaultAppBaseURL      = "http://localhost:8080"
	defaultResetTokenTTL   = time.Hour
)

type Config struct {
	Address         string
	DatabasePath    string
	ShutdownTimeout time.Duration
	JWTSecret       string
	SessionDuration time.Duration
	// AppBaseURL is the public origin of the web app. Links mailed (for now,
	// logged) to users are built from it.
	AppBaseURL         string
	ResetTokenDuration time.Duration
}

func Default() Config {
	return Config{
		Address:            environmentOrDefault("TINYSCHOOL_API_ADDRESS", defaultAddress),
		DatabasePath:       environmentOrDefault("TINYSCHOOL_DB_PATH", defaultDatabasePath),
		ShutdownTimeout:    defaultShutdownTimeout,
		JWTSecret:          os.Getenv("TINYSCHOOL_JWT_SECRET"),
		SessionDuration:    defaultSessionDuration,
		AppBaseURL:         environmentOrDefault("TINYSCHOOL_APP_BASE_URL", defaultAppBaseURL),
		ResetTokenDuration: defaultResetTokenTTL,
	}
}

func (c Config) Validate() error {
	if strings.TrimSpace(c.Address) == "" {
		return fmt.Errorf("address must not be empty")
	}
	if strings.TrimSpace(c.DatabasePath) == "" {
		return fmt.Errorf("database path must not be empty")
	}
	if c.ShutdownTimeout <= 0 {
		return fmt.Errorf("shutdown timeout must be greater than zero")
	}
	if c.JWTSecret != "" && len(c.JWTSecret) < 32 {
		return fmt.Errorf("JWT secret must be at least 32 bytes")
	}
	if c.SessionDuration <= 0 {
		return fmt.Errorf("session duration must be greater than zero")
	}
	if strings.TrimSpace(c.AppBaseURL) == "" {
		return fmt.Errorf("app base URL must not be empty")
	}
	if c.ResetTokenDuration <= 0 {
		return fmt.Errorf("reset token duration must be greater than zero")
	}
	return nil
}

// ResolveJWTSecret returns the configured secret or loads a stable, private
// local secret beside the SQLite database. It creates the file on first use.
func (c Config) ResolveJWTSecret() (string, error) {
	if c.JWTSecret != "" {
		return c.JWTSecret, nil
	}

	path := filepath.Join(filepath.Dir(c.DatabasePath), ".tinyschool-jwt-secret")
	secret, err := os.ReadFile(path)
	if err == nil {
		value := strings.TrimSpace(string(secret))
		if len(value) < 32 {
			return "", fmt.Errorf("JWT secret in %s must be at least 32 bytes", path)
		}
		return value, nil
	}
	if !os.IsNotExist(err) {
		return "", fmt.Errorf("read JWT secret: %w", err)
	}

	random := make([]byte, 32)
	if _, err := rand.Read(random); err != nil {
		return "", fmt.Errorf("generate JWT secret: %w", err)
	}
	value := hex.EncodeToString(random)
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return "", fmt.Errorf("create JWT secret directory: %w", err)
	}
	file, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		if os.IsExist(err) {
			secret, readErr := os.ReadFile(path)
			if readErr != nil {
				return "", fmt.Errorf("read concurrently created JWT secret: %w", readErr)
			}
			return strings.TrimSpace(string(secret)), nil
		}
		return "", fmt.Errorf("create JWT secret: %w", err)
	}
	if _, err := file.WriteString(value + "\n"); err != nil {
		_ = file.Close()
		return "", fmt.Errorf("write JWT secret: %w", err)
	}
	if err := file.Close(); err != nil {
		return "", fmt.Errorf("close JWT secret: %w", err)
	}
	return value, nil
}

func environmentOrDefault(name, fallback string) string {
	if value, ok := os.LookupEnv(name); ok {
		return value
	}
	return fallback
}
