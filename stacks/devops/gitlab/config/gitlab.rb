# GitLab Omnibus configuration (mounted read-only at /etc/gitlab/gitlab.rb).
# Values come from the container environment (see compose.yaml / .env) and from Docker
# secrets under /run/secrets, so this file contains no secrets and needs no templating.
# Apply changes with: docker compose restart gitlab  (or: docker compose exec gitlab gitlab-ctl reconfigure)

env_true = ->(name) { ENV.fetch(name, 'false').to_s.downcase == 'true' }
read_secret = lambda do |name|
  path = "/run/secrets/#{name}"
  File.exist?(path) ? File.read(path).strip : nil
end

external_url "https://#{ENV.fetch('GITLAB_HOST')}"

# Initial root user (only used on first initialization)
gitlab_rails['initial_root_password'] = read_secret.call('gitlab_root_password')
gitlab_rails['initial_root_email'] = ENV.fetch('GITLAB_ROOT_EMAIL', 'admin@example.com')

# GitLab Shell: the SSH port shown in clone URLs (published host port)
gitlab_rails['gitlab_shell_ssh_port'] = ENV.fetch('GITLAB_SSH_PORT', '2424').to_i

# TLS terminates at Traefik: bundled nginx listens on plain HTTP inside the container.
letsencrypt['enable'] = false
nginx['listen_port'] = 80
nginx['listen_https'] = false
nginx['real_ip_header'] = 'X-Forwarded-For'
nginx['real_ip_recursive'] = 'on'
trusted_proxies = ENV.fetch('GITLAB_TRUSTED_PROXIES', '172.16.0.0/12').split(',').map(&:strip)
nginx['real_ip_trusted_addresses'] = trusted_proxies
gitlab_rails['trusted_proxies'] = trusted_proxies
nginx['proxy_set_headers'] = {
  'X-Forwarded-Proto' => 'https',
  'X-Forwarded-Ssl' => 'on'
}

# Containers cannot change host kernel parameters (no CAP_SYS_ADMIN / sysctl).
package['modify_kernel_parameters'] = false

# Container Registry (enabled by compose.registry.yaml)
if env_true.call('GITLAB_REGISTRY_ENABLED')
  registry_external_url "https://#{ENV.fetch('GITLAB_REGISTRY_HOST')}"
  gitlab_rails['registry_enabled'] = true
  registry_nginx['listen_https'] = false
  registry_nginx['listen_port'] = 5000
  registry_nginx['proxy_set_headers'] = {
    'X-Forwarded-Proto' => 'https',
    'X-Forwarded-Ssl' => 'on'
  }
else
  gitlab_rails['registry_enabled'] = false
end

# OpenID Connect SSO, e.g. Authentik (enabled by compose.oidc.yaml)
if env_true.call('GITLAB_OIDC_ENABLED')
  gitlab_rails['omniauth_allow_single_sign_on'] = ['openid_connect']
  gitlab_rails['omniauth_block_auto_created_users'] = ENV.fetch('GITLAB_OIDC_BLOCK_AUTO_CREATED_USERS', 'true') == 'true'
  gitlab_rails['omniauth_auto_link_user'] = ['openid_connect']
  gitlab_rails['omniauth_providers'] = [
    {
      name: 'openid_connect',
      label: ENV.fetch('GITLAB_OIDC_LABEL', 'Authentik'),
      args: {
        name: 'openid_connect',
        scope: ['openid', 'profile', 'email'],
        response_type: 'code',
        issuer: ENV.fetch('GITLAB_OIDC_ISSUER'),
        discovery: true,
        client_auth_method: 'query',
        uid_field: ENV.fetch('GITLAB_OIDC_UID_FIELD', 'sub'),
        send_scope_to_token_endpoint: 'false',
        pkce: true,
        client_options: {
          identifier: ENV.fetch('GITLAB_OIDC_CLIENT_ID'),
          secret: read_secret.call('gitlab_oidc_client_secret'),
          redirect_uri: "https://#{ENV.fetch('GITLAB_HOST')}/users/auth/openid_connect/callback"
        }
      }
    }
  ]
end

# SMTP (enabled by compose.smtp.yaml)
if env_true.call('GITLAB_SMTP_ENABLED')
  gitlab_rails['smtp_enable'] = true
  gitlab_rails['smtp_address'] = ENV.fetch('GITLAB_SMTP_HOST')
  gitlab_rails['smtp_port'] = ENV.fetch('GITLAB_SMTP_PORT', '587').to_i
  gitlab_rails['smtp_user_name'] = ENV.fetch('GITLAB_SMTP_USER', '')
  gitlab_rails['smtp_password'] = read_secret.call('gitlab_smtp_password')
  gitlab_rails['smtp_authentication'] = 'login'
  gitlab_rails['smtp_domain'] = ENV.fetch('GITLAB_HOST')
  case ENV.fetch('GITLAB_SMTP_SECURITY', 'starttls')
  when 'ssl'
    gitlab_rails['smtp_tls'] = true
  else
    gitlab_rails['smtp_enable_starttls_auto'] = true
  end
  gitlab_rails['smtp_openssl_verify_mode'] = 'peer'
  gitlab_rails['gitlab_email_from'] = ENV.fetch('GITLAB_EMAIL_FROM')
  gitlab_rails['gitlab_email_reply_to'] = ENV.fetch('GITLAB_EMAIL_FROM')
end

# Resource preset for small / homelab hosts (reduces memory, lowers throughput)
if ENV.fetch('GITLAB_PERFORMANCE_PRESET', 'homelab') == 'homelab'
  postgresql['shared_buffers'] = '256MB'
  sidekiq['concurrency'] = 1
  puma['worker_timeout'] = 120
  puma['worker_processes'] = 1
end

# Bundled Prometheus/exporters (metrics stay inside the container)
prometheus_monitoring['enable'] = env_true.call('GITLAB_PROMETHEUS_ENABLED')

# Default UI settings
gitlab_rails['gitlab_default_theme'] = ENV.fetch('GITLAB_DEFAULT_THEME', '2').to_i
gitlab_rails['gitlab_default_color_mode'] = ENV.fetch('GITLAB_DEFAULT_COLOR_MODE', '2').to_i

# Product usage data (opt-out by default)
gitlab_rails['initial_gitlab_product_usage_data'] = env_true.call('GITLAB_PRODUCT_USAGE_DATA')
