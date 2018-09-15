-- Main configuration of Knot Resolver.
-- Refer to manual: https://knot-resolver.readthedocs.io/en/latest/daemon.html#configuration

nicname = env.KRESD_NIC
if nicname == nil or nicname == '' then
	io.stdout:write('Listening on all interfaces\n')
	addresses = {'0.0.0.0', '::'}
elseif net[nicname] ~= nil then
	io.stdout:write('Listening on ' .. nicname .. ' interface\n')
	addresses = net[nicname]
else
	io.stderr:write('Cannot find ' .. nicname .. ' interface\n')
	os.exit(1)
end
net.tls('/var/lib/knot-resolver/ssl/server.crt', '/var/lib/knot-resolver/ssl/server.key')
net.listen(addresses, 53)
net.listen(addresses, 853, {tls = true})

-- Load useful modules
modules = {
	'rebinding < iterate', -- Rebinding BEFORE iterate
	'hints     > iterate', -- Hints AFTER iterate
	'policy    > hints',   -- Policy AFTER hints
	'view      < cache',   -- View BEFORE cache
	'stats',
	'predict',
	http = {
		host = '::',
		port = 8053,
		key = '/var/lib/knot-resolver/ssl/server.key',
		cert = '/var/lib/knot-resolver/ssl/server.crt',
		geoip = '/var/lib/knot-resolver/geoip.mmdb'
	}
}

-- Add health check HTTP endpoint
http.endpoints['/health'] = {'text/plain', function () return 'OK' end}

-- Smaller cache size
cache.size = 10 * MB

-- Add rules for special-use and locally-served domains
-- https://www.iana.org/assignments/special-use-domain-names/
-- https://www.iana.org/assignments/locally-served-dns-zones/
for _, rule in ipairs(policy.special_names) do
	policy.add(rule.cb)
end

-- Add blacklist zone
policy.add(policy.rpz(
	policy.DENY_MSG('Blacklisted domain'),
	'/var/lib/knot-resolver/hblock.rpz'
))

-- DNS over TLS forwarding
tls_ca_bundle = '/etc/ssl/certs/ca-certificates.crt'
policy.add(policy.all(policy.TLS_FORWARD({
	-- Cloudflare (https://1.1.1.1)
	{'1.1.1.1', hostname='cloudflare-dns.com', ca_file=tls_ca_bundle},
	{'2606:4700:4700::1111', hostname='cloudflare-dns.com', ca_file=tls_ca_bundle},
	{'1.0.0.1', hostname='cloudflare-dns.com', ca_file=tls_ca_bundle},
	{'2606:4700:4700::1001', hostname='cloudflare-dns.com', ca_file=tls_ca_bundle}
	-- Quad9 filtered (https://www.quad9.net)
	--{'9.9.9.9', hostname='dns.quad9.net', ca_file=tls_ca_bundle},
	--{'2620:fe::fe', hostname='dns.quad9.net', ca_file=tls_ca_bundle},
	-- Quad9 unfiltered (https://www.quad9.net)
	--{'9.9.9.10', hostname='dns.quad9.net', ca_file=tls_ca_bundle},
	--{'2620:fe::10', hostname='dns.quad9.net', ca_file=tls_ca_bundle},
})))

-- Enable verbose logging
-- verbose(true)

-- Load extra configuration
extra_conf_path = '/var/lib/knot-resolver/kresd.extra.conf'
extra_conf_file = io.open(extra_conf_path, 'r')
if extra_conf_file ~= nil then
	io.close(extra_conf_file)
	dofile(extra_conf_path)
end
