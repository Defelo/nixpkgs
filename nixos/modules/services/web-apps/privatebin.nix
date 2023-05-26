{
  lib,
  pkgs,
  config,
  ...
}: let
  user = "privatebin";
  group = user;
  cfg = config.services.privatebin;
  envVar = lib.mkOptionType {
    name = "environment variable";
    description = "attribute set with _env as string";
    descriptionClass = "composite";
    check = x: lib.isAttrs x && x ? _env && lib.types.nonEmptyStr.check x._env;
  };
  isEnv = v: lib.isAttrs v && v ? _env && lib.isString v._env;
  format = let
    iniAtom = (pkgs.formats.ini {}).type.functor.wrapped.functor.wrapped;
  in
    pkgs.formats.ini {}
    // {
      type = lib.types.attrsOf (lib.types.attrsOf (lib.types.either iniAtom envVar));
    };

  expire_options = finalCfg.expire_options or {};
  expire_lines = let
    toList = lib.mapAttrsToList (key: value: {inherit key value;});
    sortExpire = builtins.sort (a: b: (a.value < b.value) && a.value != 0);
  in
    map (v: "${v.key}=${toString v.value}") (sortExpire (toList expire_options));

  toIni = lib.generators.toINI {
    mkKeyValue = lib.flip lib.generators.mkKeyValueDefault "=" {
      mkValueString = v:
        if lib.isString v
        then ''"${toString v}"''
        else if isEnv v
        then "\${${v._env}}"
        else lib.generators.mkValueStringDefault {} v;
    };
  };

  configFile = pkgs.writeTextDir "conf.php" ''
    ;<?php http_response_code(403); /*
    ${toIni (builtins.removeAttrs finalCfg ["expire_options"])}
    ${lib.optionalString (expire_options != {}) ''
      [expire_options]
      ${lib.concatStringsSep "\n" expire_lines}
    ''}
    ;*/
  '';

  autoDb =
    if !cfg.databaseSetup.enable
    then null
    else cfg.databaseSetup.kind;
  db_config = lib.optionalAttrs (autoDb != null) (
    if autoDb == "mysql"
    then {
      model.class = "Database";
      model_options = {
        dsn = "mysql:unix_socket=/run/mysqld/mysqld.sock;dbname=${user}";
        usr = user;
      };
    }
    else if autoDb == "pgsql"
    then {
      model.class = "Database";
      model_options.dsn = "pgsql:host=/run/postgresql;port=${toString config.services.postgresql.port};dbname=${user}";
    }
    else {
      model.class = "Database";
      model_options.dsn = "sqlite:/var/lib/privatebin/data/db.sqlite3";
    }
  );
  finalCfg = lib.recursiveUpdate cfg.settings db_config;
in {
  meta.maintainers = with lib.maintainers; [e1mo defelo];

  options.services.privatebin = {
    enable = lib.mkEnableOption "PrivateBin web application";

    package = lib.mkPackageOption pkgs "privatebin" {};

    settings = lib.mkOption {
      inherit (format) type;
      default = {};
      example = lib.literalExpression ''
        {
          main = {
            name._env = "PRIVATEBIN_NAME";
            basepath = "https://privatebin.example.com/";
            fileupload = true;
            syntaxhighlightingtheme = "sons-of-obsidian";
            info = "This instance of PrivateBin is hosted on NixOS!";
            languageselection = true;
            icon = "none";
            cspheader = "default-src 'none'; base-uri 'self'; form-action 'none'; manifest-src 'self'; connect-src * blob:; script-src 'self' 'unsafe-eval'; style-src 'self'; font-src 'self'; frame-ancestors 'none'; img-src 'self' data: blob:; media-src blob:; object-src blob:; sandbox allow-same-origin allow-scripts allow-forms allow-popups allow-modals allow-downloads";
            httpwarning = true;
          };
          expire.default = "1day";
          traffic = {
            limit = 10;
            exempted = "1.2.3.4,10.10.10/24";
          };
          purge = {
            limit = 300;
            batchsize = 10;
          };
          model = {
            class = "Database";
          };
          model_options = {
            dsn = "pgsql:host=localhost;dbname=privatebin";
            tbl = "privatebin_";
            user = "privatebin";
            pwd._env = "PRIVATEBIN_DB_PASS";
          };
        }
      '';
      description = ''
        Privatebin configuration as outlined in
        <https://github.com/PrivateBin/PrivateBin/wiki/Configuration>.

        Available sections are `[main]`, `[expire]`, `[expire_options]`,
        `[formatter_options]`, `[traffic]`, `[purge]`, `[model]`,
        `[model_options]` and `[yourls]`.
      '';
    };

    environmentFiles = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      description = "Optional files containing environment variables with secrets to be passed to the config";
      default = [];
    };

    databaseSetup = {
      enable = lib.mkEnableOption "Automatic database setup and configuration";
      kind = lib.mkOption {
        type = lib.types.enum ["pgsql" "mysql" "sqlite"];
        description = "Type of database to automatically set up";
        default = "sqlite";
      };
    };

    poolConfig = lib.mkOption {
      type = lib.types.attrsOf (lib.types.oneOf [lib.types.str lib.types.int lib.types.bool]);
      default = {
        "pm" = "ondemand";
        "pm.max_children" = 10;
        "pm.process_idle_timeout" = "30s";
        "pm.max_requests" = 200;
      };
      description = ''
        Options for the PrivateBin PHP pool. See the documentation on `php-fpm.conf`
        for details on configuration directives.
      '';
    };

    phpPackage = lib.mkPackageOption pkgs "php" {};

    phpOptions = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = ''
        Options for PHP's php.ini file for this dokuwiki site.
      '';
      example = lib.literalExpression ''
        {
          "opcache.interned_strings_buffer" = "8";
          "opcache.max_accelerated_files" = "10000";
          "opcache.memory_consumption" = "128";
          "opcache.revalidate_freq" = "15";
          "opcache.fast_shutdown" = "1";
        }
      '';
    };

    nginx = lib.mkOption {
      type = lib.types.submodule (import ../web-servers/nginx/vhost-options.nix {inherit config lib;});
      default = {};
      example = lib.literalExpression ''
        {
          forceSSL = true;
          enableACME = true;
        }
      '';
      description = ''
        Optional settings to pass to the nginx virtualHost.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${user} = {
      inherit group;
      isSystemUser = true;
      createHome = false;
    };
    users.users.${config.services.nginx.user} = lib.mkIf config.services.nginx.enable {extraGroups = [group];};
    users.groups.${group} = {};

    services.phpfpm.pools.${user} = {
      inherit user group;
      settings =
        {
          "listen.mode" = "0660";
          "listen.owner" = user;
          "listen.group" = group;
          "catch_workers_output" = true;
          "clear_env" = false;
        }
        // cfg.poolConfig;
      phpEnv.CONFIG_PATH = "${configFile}";
    };

    services.postgresql = lib.mkIf (autoDb == "pgsql") {
      enable = true;
      ensureUsers = [
        {
          name = user;
          ensureDBOwnership = true;
        }
      ];
      ensureDatabases = [
        user
      ];
    };

    services.mysql = lib.mkIf (autoDb == "mysql") {
      enable = true;
      package = lib.mkDefault pkgs.mariadb;
      ensureUsers = [
        {
          name = user;
          ensurePermissions = {
            "${user}.*" = "ALL PRIVILEGES";
          };
        }
      ];
      ensureDatabases = [
        user
      ];
    };
    systemd.services."phpfpm-${user}".serviceConfig = {
      ProtectSystem = "full";
      PrivateTmp = true;
      EnvironmentFile = cfg.environmentFiles;
    };
    systemd.tmpfiles.rules = [
      "d /var/lib/privatebin/data 0750 ${user} ${group} - -"
    ];

    services.nginx = {
      enable = lib.mkDefault true;
      virtualHosts.privatebin = lib.mkMerge [
        cfg.nginx
        {
          root = lib.mkForce pkgs.privatebin;
          extraConfig = lib.optionalString (cfg.nginx.addSSL || cfg.nginx.forceSSL || cfg.nginx.onlySSL) "fastcgi_param HTTPS on;";
          locations = {
            "/".index = "index.php";
            "~ \.php$" = {
              extraConfig = ''
                try_files $uri $uri/ /index.php?$query_string;
                include ${pkgs.nginx}/conf/fastcgi.conf;
                fastcgi_param REDIRECT_STATUS 200;
                fastcgi_pass unix:${config.services.phpfpm.pools.${user}.socket};
                ${lib.optionalString (cfg.nginx.addSSL || cfg.nginx.forceSSL || cfg.nginx.onlySSL) "fastcgi_param HTTPS on;"}
              '';
            };
          };
        }
      ];
    };
  };
}
