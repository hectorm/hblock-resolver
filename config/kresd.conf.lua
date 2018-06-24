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
net.listen(addresses, 53)
net.listen(addresses, 853, {tls = true})

-- Drop root privileges
user('knot-resolver', 'knot-resolver')

-- Load useful modules
modules = {
	'policy', -- Load policy module
	'hints', -- Load hints module
	'stats', -- Track internal statistics
	'predict', -- Prefetch expiring/frequent records
	-- Load HTTP module
	http = {
		host = '::',
		port = 8053,
		key = '/var/lib/knot-resolver/ssl/self.key',
		cert = '/var/lib/knot-resolver/ssl/self.crt',
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
	'/var/lib/knot-resolver/blacklist.rpz'
))

-- DNS over TLS forwarding
tls_ca_bundle = '/etc/ssl/certs/ca-certificates.crt'
policy.add(policy.all(policy.TLS_FORWARD({
	-- Cloudflare
	{'1.1.1.1', hostname='cloudflare-dns.com', ca_file=tls_ca_bundle},
	{'2606:4700:4700::1111', hostname='cloudflare-dns.com', ca_file=tls_ca_bundle},
	{'1.0.0.1', hostname='cloudflare-dns.com', ca_file=tls_ca_bundle},
	{'2606:4700:4700::1001', hostname='cloudflare-dns.com', ca_file=tls_ca_bundle}
})))

-- Enable verbose logging
-- verbose(true)
