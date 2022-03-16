admin: {
  disabled: true
}

logging: logs: {
  default: exclude: ["http.log.access.main"]
  main: {
    include: ["http.log.access.main"]
    writer: output: "stdout"
    encoder: {
      format: "formatted"
      template: #"{common_log} "{request>headers>Referer>[0]}" "{request>headers>User-Agent>[0]}""#
    }
  }
}

apps: {
  http: servers: {
    http: {
      listen: [":80"]
      routes: [{
        match: [{ host: ["{$TLS_DOMAIN}"] }]
        handle: [{
          handler: "static_response"
          status_code: 301
          headers: {
            Location: ["https://{http.request.host}{http.request.uri}"]
          }
        }]
      }]
      automatic_https: disable: true
      logs: default_logger_name: "main"
    }
    https: {
      listen: [":443"]
      routes: [{
        match: [{ host: ["{$TLS_DOMAIN}"] }]
        handle: [{
          handler: "subroute"
          routes: [{
            // DNS-over-HTTPS endpoint
            match: [{ path: ["/dns-query"] }]
            handle: [{
              handler: "reverse_proxy"
              upstreams: [{ dial: "hblock-resolver:443" }]
              transport: {
                protocol: "http"
                tls: insecure_skip_verify: true
                keep_alive: enabled: false
              }
            }]
          }, {
            // Web management endpoint
            match: [{ path: ["/*"] }]
            handle: [{
              handler: "reverse_proxy"
              upstreams: [{ dial: "hblock-resolver:8453" }]
              transport: {
                protocol: "http"
                tls: insecure_skip_verify: true
              }
            }]
          }]
        }]
      }]
      automatic_https: disable_redirects: true
      tls_connection_policies: [{
        match: sni: ["{$TLS_DOMAIN}", ""]
        default_sni: "{$TLS_DOMAIN}"
      }]
      logs: default_logger_name: "main"
    }
  }
  layer4: servers: {
    dot: {
      listen: [":853"]
      routes: [{
        // DNS-over-TLS endpoint
        match: [{ tls: { } }]
        handle: [{
          handler: "tls"
          connection_policies: [{
            alpn: ["dot"]
            match: sni: ["{$TLS_DOMAIN}", ""]
            default_sni: "{$TLS_DOMAIN}"
          }]
        }, {
          handler: "proxy"
          upstreams: [{
            dial: ["hblock-resolver:853"]
            tls: insecure_skip_verify: true
          }]
        }]
      }]
    }
  }
  tls: automation: policies: [{
    subjects: ["{$TLS_DOMAIN}"]
    issuers: [{
      module: "{$TLS_MODULE}"
      ca: "{$TLS_CA}"
      if "{$TLS_MODULE}" == "acme" {
        email: "{$TLS_EMAIL}"
      }
    }]
  }]
  pki: certificate_authorities: local: {
    install_trust: false
  }
}
