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
net.listen(addresses, 853, {tls=true})

-- Drop root privileges
user('knot-resolver', 'knot-resolver')

-- Load useful modules
modules = {
	'hints > iterate', -- Load hints after iterator
	'policy', -- Block queries to local zones/bad sites
	'stats', -- Track internal statistics
	'predict', -- Prefetch expiring/frequent records
	-- Load HTTP module with defaults
	http = {
		host = '::',
		port = 8053,
		key = '/var/lib/knot-resolver/ssl/self.key',
		cert = '/var/lib/knot-resolver/ssl/self.crt',
		geoip = '/var/lib/knot-resolver/geoip.mmdb',
		endpoints = {
			['/health'] = {'text/plain', function () return 'OK' end}
		}
	}
}

-- Smaller cache size
cache.size = 10 * MB

-- Add blacklist zone
policy.add(policy.rpz(policy.DENY, '/var/lib/knot-resolver/blacklist.rpz'))

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
