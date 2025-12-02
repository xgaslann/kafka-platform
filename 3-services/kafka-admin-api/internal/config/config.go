package config

import (
	"github.com/kelseyhightower/envconfig"
)

type Config struct {
	Port             string `envconfig:"PORT" default:"2020"`
	BootstrapServers string `envconfig:"KAFKA_BOOTSTRAP_SERVERS" required:"true"`
	SASLUsername     string `envconfig:"KAFKA_SASL_USERNAME"`
	SASLPassword     string `envconfig:"KAFKA_SASL_PASSWORD"`
	CALocation       string `envconfig:"KAFKA_CA_LOCATION"`
}

func Load() (*Config, error) {
	var cfg Config
	if err := envconfig.Process("", &cfg); err != nil {
		return nil, err
	}
	return &cfg, nil
}
