{ config, ... }:
{
  services.grafana = {
    enable = true;
    settings = {
      analytics.reporting_enabled = false;

      "auth.anonymous".enabled = false;

      # https://grafana.com/docs/grafana/latest/setup-grafana/configure-security/configure-authentication/github/
      "auth.github" = {
        enabled = true;
        client_id = "";
        client_secret = "";
        auth_url = "";
        token_url = "";
        api_url = "";
        allow_sign_up = true;
        auto_login = false;
        allowed_organizations = [ "nix-community" ];
        role_attribute_strict = true;
        allow_assign_grafana_admin = true;
        role_attribute_path = "contains(groups[*], '@nix-community/admin') && 'GrafanaAdmin' || 'Editor'";
      };

      server = {
        root_url = "https:/monitoring.nix-community.org/grafana/";
        domain = "monitoring.nix-community.org";
        enforce_domain = true;
        enable_gzip = true;
        serve_from_sub_path = true;
      };

      database = {
        type = "postgres";
        name = "grafana";
        host = "/run/postgresql";
        user = "grafana";
      };

      security.admin_password = "$__file{${config.sops.secrets.grafana-admin-password.path}}";
    };
  };

  sops.secrets.grafana-admin-password.owner = "grafana";

  services.postgresql = {
    enable = true;
    ensureDatabases = [ "grafana" ];
    ensureUsers = [
      {
        name = "grafana";
        ensurePermissions = { "DATABASE grafana" = "ALL PRIVILEGES"; };
      }
    ];
  };

  services.postgresqlBackup = {
    enable = true;
    compression = "none";
    startAt = "daily";
    databases = [ "grafana" ];
  };

  sops.secrets.hetzner-borgbackup-passphrase = { };
  sops.secrets.hetzner-borgbackup-ssh = { };

  systemd.services.borgbackup-job-grafana-postgresql = {
    after = [ "postgresqlBackup.service" ];
    serviceConfig.ReadWritePaths = [
      "/var/log/telegraf"
    ];
  };

  services.borgbackup.jobs.grafana-postgresql = {
    paths = [
      "/var/backup/postgresql"
    ];
    repo = "u348918@u348918.your-storagebox.de:/./grafana-postgresql";
    encryption = {
      mode = "repokey";
      passCommand = "cat ${config.sops.secrets.hetzner-borgbackup-passphrase.path}";
    };
    compression = "auto,zstd";
    startAt = "daily";
    environment.BORG_RSH = "ssh -oPort=23 -i ${config.sops.secrets.hetzner-borgbackup-ssh.path}";
    preHook = ''
      set -x
    '';
    postHook = ''
      cat > /var/log/telegraf/borgbackup-job-grafana-postgresql.service <<EOF
      task,frequency=daily last_run=$(date +%s)i,state="$([[ $exitStatus == 0 ]] && echo ok || echo fail)"
      EOF
    '';

    prune.keep = {
      within = "1d"; # Keep all archives from the last day
      daily = 7;
      weekly = 4;
      monthly = 0;
    };
  };
}
