package config

import (
	"fmt"
	"net"
	"net/url"
	"os"
	"strconv"
	"strings"
)

type Config struct {
	Port        int
	DatabaseURL string
	Version     string
	Commit      string
}

func FromEnv() (Config, error) {
	port := 8080
	if raw := strings.TrimSpace(os.Getenv("PORT")); raw != "" {
		parsed, err := strconv.Atoi(raw)
		if err != nil {
			return Config{}, fmt.Errorf("PORT must be a number: %w", err)
		}
		port = parsed
	}
	result := Config{
		Port:        port,
		DatabaseURL: strings.TrimSpace(os.Getenv("DATABASE_URL")),
		Version:     strings.TrimSpace(os.Getenv("BUILD_VERSION")),
		Commit:      strings.TrimSpace(os.Getenv("BUILD_COMMIT")),
	}
	if result.DatabaseURL == "" {
		host := strings.TrimSpace(os.Getenv("DB_HOST"))
		port := strings.TrimSpace(os.Getenv("DB_PORT"))
		name := strings.TrimSpace(os.Getenv("DB_NAME"))
		user := strings.TrimSpace(os.Getenv("DB_USER"))
		password := os.Getenv("DB_PASSWORD")
		if host == "" || port == "" || name == "" || user == "" || password == "" {
			return Config{}, fmt.Errorf("DATABASE_URL or all DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD variables are required")
		}
		parsedPort, err := strconv.Atoi(port)
		if err != nil || parsedPort < 1 || parsedPort > 65535 {
			return Config{}, fmt.Errorf("DB_PORT must be between 1 and 65535")
		}
		result.DatabaseURL = (&url.URL{
			Scheme:   "postgres",
			User:     url.UserPassword(user, password),
			Host:     net.JoinHostPort(host, port),
			Path:     "/" + name,
			RawQuery: "sslmode=disable",
		}).String()
	}
	if err := result.Validate(); err != nil {
		return Config{}, err
	}
	return result, nil
}

func (c Config) Validate() error {
	if c.Port < 1 || c.Port > 65535 {
		return fmt.Errorf("PORT must be between 1 and 65535")
	}
	if c.DatabaseURL == "" {
		return fmt.Errorf("DATABASE_URL is required")
	}
	if !strings.HasPrefix(c.DatabaseURL, "postgres://") && !strings.HasPrefix(c.DatabaseURL, "postgresql://") {
		return fmt.Errorf("DATABASE_URL must use postgres:// or postgresql://")
	}
	return nil
}
