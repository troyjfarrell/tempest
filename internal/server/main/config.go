package servermain

import (
	"net"
	"net/smtp"
	"net/url"

	"golang.org/x/exp/slog"
	"sandstorm.org/go/tempest/internal/server/logging"
	"sandstorm.org/go/tempest/internal/server/settings"
	"zenhack.net/go/util"
)

type Config struct {
	HTTP HTTPConfig
	SMTP SMTPConfig
}

type HTTPConfig struct {
	RootDomain        string // Main Tempest domain name
	Port              string
	TLSPort           string
	CertFile, KeyFile string
	DefaultTLS        bool
}

type SMTPConfig struct {
	Host     string
	Port     string
	Username string
	Password string
}

func (c SMTPConfig) getAuth() smtp.Auth {
	return smtp.PlainAuth(
		c.Username,
		c.Username,
		c.Password,
		c.Host,
	)
}

func (c SMTPConfig) SendMail(to []string, msg []byte) error {
	return smtp.SendMail(
		net.JoinHostPort(c.Host, c.Port),
		c.getAuth(),
		c.Username,
		to,
		msg,
	)
}

func SMTPConfigFromSettings(src settings.Source) SMTPConfig {
	return SMTPConfig{
		Host:     src.GetString("SMTP_HOST"),
		Port:     src.GetString("SMTP_PORT"),
		Username: src.GetString("SMTP_USERNAME"),
		Password: src.GetString("SMTP_PASSWORD"),
	}
}

func HTTPConfigFromSettings(lg *slog.Logger, src settings.Source) HTTPConfig {
	baseURLStr := src.GetString("BASE_URL")
	baseURL := util.Must(url.Parse(baseURLStr))
	if baseURL.Scheme != "http" && baseURL.Scheme != "https" {
		logging.Panic(lg, "parsing BASE_URL: must use http(s) scheme")
	}
	if baseURL.Path != "" {
		logging.Panic(lg, "parsing BASE_URL: must not have a path")
	}
	cfg := HTTPConfig{
		DefaultTLS: baseURL.Scheme == "https",
		RootDomain: baseURL.Host,
		Port:       src.GetString("HTTP_PORT"),
		TLSPort:    src.GetString("HTTPS_PORT"),
		CertFile:   src.GetString("HTTPS_CERT_FILE"),
		KeyFile:    src.GetString("HTTPS_KEY_FILE"),
	}
	return cfg
}

func ConfigFromSettings(lg *slog.Logger, src settings.Source) Config {
	return Config{
		HTTP: HTTPConfigFromSettings(lg, src),
		SMTP: SMTPConfigFromSettings(src),
	}
}
