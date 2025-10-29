https://github.com/spantaleev/matrix-docker-ansible-deploy
https://github.com/element-hq/ess-helm


Caddyfile inspiration:
# =========================
# Matrix Services (client + federation)
# =========================
matrix.mair.io, matrix.mair.io:8448, matrix.mair.is, matrix.mair.is:8448 {

  # Well-known (public)
  @wk path /.well-known/matrix/client
  handle @wk {
    header Content-Type application/json
    respond `{"m.homeserver":{"base_url":"https://matrix.mair.io"},"m.authentication":{"m.oauth2":{"issuer":"https://account.matrix.mair.io>
  }
  # Client versions endpoint (add CORS headers)
  @versions path /_matrix/client/versions
  handle @versions {
    header Access-Control-Allow-Origin "*"
    header Access-Control-Allow-Methods "GET, OPTIONS"
    header Access-Control-Allow-Headers "Authorization, Content-Type, Accept"
    header Vary "Origin, Access-Control-Request-Method, Access-Control-Request-Headers"
    reverse_proxy http://matrix.horn:8008 {
      header_down -Access-Control-Allow-Origin
      header_down -Access-Control-Allow-Methods
      header_down -Access-Control-Allow-Headers
      header_down -Vary
      header_down X-Routed-By SYNAPSE-VERSIONS
    }
  }



root@caddy:/etc/caddy/conf.d# cat matrix.caddyfile 
# =========================
# Matrix Services (client + federation)
# =========================
matrix.mair.io, matrix.mair.io:8448, matrix.mair.is, matrix.mair.is:8448 {

  # Well-known (public)
  @wk path /.well-known/matrix/client
  handle @wk {
    header Content-Type application/json
    respond `{"m.homeserver":{"base_url":"https://matrix.mair.io"},"m.authentication":{"m.oauth2":{"issuer":"https://account.matrix.mair.io"}}}`
  }
  # Client versions endpoint (add CORS headers)
  @versions path /_matrix/client/versions
  handle @versions {
    header Access-Control-Allow-Origin "*"
    header Access-Control-Allow-Methods "GET, OPTIONS"
    header Access-Control-Allow-Headers "Authorization, Content-Type, Accept"
    header Vary "Origin, Access-Control-Request-Method, Access-Control-Request-Headers"
    reverse_proxy http://matrix.horn:8008 {
      header_down -Access-Control-Allow-Origin
      header_down -Access-Control-Allow-Methods
      header_down -Access-Control-Allow-Headers
      header_down -Vary
      header_down X-Routed-By SYNAPSE-VERSIONS
    }
  }

  # CORS preflight for auth metadata
  @auth_preflight {
    method OPTIONS
    path /_matrix/client/unstable/org.matrix.msc2965/auth_metadata
  }
  handle @auth_preflight {
    header Access-Control-Allow-Origin "*"
    header Access-Control-Allow-Methods "GET, OPTIONS"
    header Access-Control-Allow-Headers "Authorization, Content-Type, Accept"
    header Access-Control-Max-Age "86400"
    respond 204
  }

  # CORS preflight for all other Matrix API
  @preflight {
    method OPTIONS
    path_regexp matrix ^/_matrix/.*$
  }
  handle @preflight {
    header Access-Control-Allow-Origin "*"
    header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS"
    header Access-Control-Allow-Headers "Authorization, Content-Type, Accept"
    header Access-Control-Max-Age "86400"
    respond 204
  }

  # Authentication metadata endpoint - handle locally since MAS doesn't support it
  @auth_metadata path /_matrix/client/unstable/org.matrix.msc2965/auth_metadata
  handle @auth_metadata {
    header Access-Control-Allow-Origin "*"
    header Access-Control-Allow-Methods "GET, OPTIONS"
    header Access-Control-Allow-Headers "Authorization, Content-Type, Accept"
    header Content-Type "application/json"
    respond `{"issuer":"https://account.matrix.mair.io/","authorization_endpoint":"https://account.matrix.mair.io/oauth2/authorize","token_endpoint":"https://account.matrix.mair.io/oauth2/token","userinfo_endpoint":"https://account.matrix.mair.io/oauth2/userinfo","jwks_uri":"https://account.matrix.mair.io/oauth2/keys.json","registration_endpoint":"https://account.matrix.mair.io/oauth2/registration","scopes_supported":["openid","profile","email"],"response_types_supported":["code"],"grant_types_supported":["authorization_code","refresh_token"],"code_challenge_methods_supported":["S256"],"token_endpoint_auth_methods_supported":["client_secret_basic","client_secret_post","none"],"revocation_endpoint":"https://account.matrix.mair.io/oauth2/revoke","account_management_uri":"https://account.matrix.mair.io/account/","account_management_actions_supported":["org.matrix.profile","org.matrix.sessions_list","org.matrix.session_view","org.matrix.session_end","org.matrix.cross_signing_reset"]}` 200
  }

  # MAS compat endpoints (login/logout/refresh + subpaths) - add CORS headers
  @compat path \
  /_matrix/client/v3/login* \
  /_matrix/client/v3/logout* \
  /_matrix/client/v3/refresh* \
  /_matrix/client/r0/login* \
  /_matrix/client/r0/logout* \
  /_matrix/client/r0/refresh*
  handle @compat {
    header Access-Control-Allow-Origin "*"
    header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS"
    header Access-Control-Allow-Headers "Authorization, Content-Type, Accept"
    header Vary "Origin, Access-Control-Request-Method, Access-Control-Request-Headers"
    reverse_proxy http://matrix.horn:8080 {
      header_down -Access-Control-Allow-Origin
      header_down -Access-Control-Allow-Methods
      header_down -Access-Control-Allow-Headers
      header_down -Vary
      header_down X-Routed-By MAS
    }
  }

  # MSC2965 SSO redirect (add CORS headers)
  @msc2965 path /_matrix/client/unstable/org.matrix.msc2965/login/sso/*
  handle @msc2965 {
    header Access-Control-Allow-Origin "*"
    header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS"
    header Access-Control-Allow-Headers "Authorization, Content-Type, Accept"
    header Vary "Origin, Access-Control-Request-Method, Access-Control-Request-Headers"
    reverse_proxy http://matrix.horn:8080 {
      header_down -Access-Control-Allow-Origin
      header_down -Access-Control-Allow-Methods
      header_down -Access-Control-Allow-Headers
      header_down -Vary
      header_down X-Routed-By MAS-MSC2965
    }
  }

  # Everything else under /_matrix → Synapse (add CORS headers)
  @matrix_rest path_regexp matrix ^/_matrix/.*$
  handle @matrix_rest {
    header Access-Control-Allow-Origin "*"
    header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS"
    header Access-Control-Allow-Headers "Authorization, Content-Type, Accept"
    header Vary "Origin, Access-Control-Request-Method, Access-Control-Request-Headers"
    reverse_proxy http://matrix.horn:8008 {
      header_down -Access-Control-Allow-Origin
      header_down -Access-Control-Allow-Methods
      header_down -Access-Control-Allow-Headers
      header_down -Vary
      header_down X-Routed-By SYNAPSE
    }
  }

  # Anything not /_matrix/* -> Synapse
  handle {
    reverse_proxy http://matrix.horn:8008
  }

  import common_logging "matrix"
}

# =========================
# MAS (OIDC) service
# =========================
account.matrix.mair.io account.matrix.mair.is {
    import common_security
    import common_logging "matrix-mas"

    # === OIDC Discovery ===
    @disco path /.well-known/openid-configuration
    handle @disco {
        header ?Access-Control-Allow-Origin "*"
        header ?Access-Control-Allow-Methods "GET, OPTIONS"
        header ?Access-Control-Allow-Headers "*"
        reverse_proxy matrix.horn:8080
    }

    # === Dynamic Client Registration: CORS preflight ===
    @reg_opts {
        method OPTIONS
        path /oauth2/registration
    }
    handle @reg_opts {
        header ?Access-Control-Allow-Origin "*"
        header ?Access-Control-Allow-Methods "POST, OPTIONS"
        header ?Access-Control-Allow-Headers "*"
        respond 204
    }

    # === Dynamic Client Registration (POST) ===
    @reg path /oauth2/registration
    route @reg {
        header ?Access-Control-Allow-Origin "*"
        header ?Access-Control-Allow-Methods "POST, OPTIONS"
        header ?Access-Control-Allow-Headers "*"
        reverse_proxy matrix.horn:8080
    }

    # === JWKS preflight ===
    @jwks_opts {
        method OPTIONS
        path /oauth2/keys.json
    }
    handle @jwks_opts {
        header ?Access-Control-Allow-Origin "*"
        header ?Access-Control-Allow-Methods "GET, OPTIONS"
        header ?Access-Control-Allow-Headers "*"
        respond 204
    }

    # === Map keys.json → /oauth2/jwks (MAS) ===
    @jwksjson path /oauth2/keys.json
    route @jwksjson {
        header ?Access-Control-Allow-Origin "*"
        header ?Access-Control-Allow-Methods "GET, OPTIONS"
        header ?Access-Control-Allow-Headers "*"
        uri replace /oauth2/keys.json /oauth2/jwks
        reverse_proxy matrix.horn:8080
    }

    # === Generic OAuth2 endpoints ===
    @oauth path /oauth2/*
    route @oauth {
        header ?Access-Control-Allow-Origin "*"
        header ?Access-Control-Allow-Methods "GET, OPTIONS, POST"
        header ?Access-Control-Allow-Headers "*"
        reverse_proxy matrix.horn:8080
    }

    # Account portal
    handle_path /account/* {
        reverse_proxy matrix.horn:8080
    }

    # Fallback: everything else to MAS
    handle {
        reverse_proxy matrix.horn:8080
    }

    # Helpful: add CORS even on error responses so the browser console isn't misleading
    handle_errors {
        header ?Access-Control-Allow-Origin "*"
        header ?Access-Control-Allow-Headers "*"
        header ?Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS"
    }
}

# =========================
# Element Web Client
# =========================
element.mair.io, element.mair.is {
  @cfg1 path /config.json
  handle @cfg1 {
    header Content-Type application/json
    header Cache-Control no-store
    respond `{
      "default_server_config": {
        "m.homeserver": {
          "base_url": "https://matrix.mair.io",
          "server_name": "mair.io"
        }
      },
      "default_server_name": "mair.io",
      "disable_custom_urls": true,
      "disable_guests": true,
      "features": {
        "feature_oidc_aware_navigation": true
      }
    }` 200
  }

  @cfg2 path /config.element.mair.io.json
  handle @cfg2 {
    header Content-Type application/json
    header Cache-Control no-store
    respond `{
      "default_server_config": {
        "m.homeserver": {
          "base_url": "https://matrix.mair.io",
          "server_name": "mair.io"
        }
      },
      "default_server_name": "mair.io",
      "disable_custom_urls": true,
      "disable_guests": true,
      "features": {
        "feature_oidc_aware_navigation": true
      }
    }` 200
  }

  # Your app (add auth back if you want; keep config paths public)
  handle {
    reverse_proxy http://matrix.horn:80
  }

  import common_logging "element"
}