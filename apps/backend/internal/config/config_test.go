package config

import "testing"

func TestDatabaseFieldsEncodePassword(t *testing.T) {
	t.Setenv("PORT", "8080")
	t.Setenv("DATABASE_URL", "")
	t.Setenv("DB_HOST", "demo-postgres")
	t.Setenv("DB_PORT", "5432")
	t.Setenv("DB_NAME", "kubedeploy")
	t.Setenv("DB_USER", "kubedeploy")
	t.Setenv("DB_PASSWORD", "a:b@c")
	cfg, err := FromEnv()
	if err != nil {
		t.Fatal(err)
	}
	if cfg.DatabaseURL != "postgres://kubedeploy:a%3Ab%40c@demo-postgres:5432/kubedeploy?sslmode=disable" {
		t.Fatalf("password was not URL-escaped")
	}
}

func TestFromEnv(t *testing.T) {
	t.Setenv("PORT", "9090")
	t.Setenv("DATABASE_URL", "postgres://user:secret@localhost:5432/kubedeploy")
	t.Setenv("BUILD_VERSION", "sha-123")
	t.Setenv("BUILD_COMMIT", "123")
	cfg, err := FromEnv()
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Port != 9090 || cfg.Version != "sha-123" || cfg.Commit != "123" {
		t.Fatalf("unexpected config: %+v", cfg)
	}
}

func TestInvalidConfig(t *testing.T) {
	tests := []struct {
		name string
		port string
		url  string
	}{
		{"missing database", "8080", ""},
		{"invalid port", "abc", "postgres://localhost/db"},
		{"out of range port", "65536", "postgres://localhost/db"},
		{"invalid scheme", "8080", "http://localhost/db"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Setenv("PORT", tc.port)
			t.Setenv("DATABASE_URL", tc.url)
			if _, err := FromEnv(); err == nil {
				t.Fatal("expected validation error")
			}
		})
	}
}
