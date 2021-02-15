# frozen_string_literal: true

module StubRequests
  IP_ADDRESS_STUB = '8.8.8.9'.freeze

  # Fully stubs a request using WebMock class. This class also
  # stubs the IP address the URL is translated to (DNS lookup).
  #
  # It expects the final request to go to the `ip_address` instead the given url.
  # That's primarily a DNS rebind attack prevention of Gitlab::HTTP
  # (see: Gitlab::UrlBlocker).
  #
  def stub_full_request(url, ip_address: IP_ADDRESS_STUB, port: 80, method: :get)
    stub_dns(url, ip_address: ip_address, port: port)

    url = stubbed_hostname(url, hostname: ip_address)
    WebMock.stub_request(method, url)
  end

  def stub_dns(url, ip_address:, port: 80)
    url = URI(url)
    socket = Socket.sockaddr_in(port, ip_address)
    addr = Addrinfo.new(socket)

    allow(Addrinfo).to receive(:getaddrinfo)
      .with(url.hostname, url.port, any_args)
      .and_return([addr])
  end

  def stub_all_dns(url, ip_address:)
    url = URI(url)
    port = 80 # arbitarily chosen, does not matter as we are not going to connect
    socket = Socket.sockaddr_in(port, ip_address)
    addr = Addrinfo.new(socket)

    allow(Addrinfo).to receive(:getaddrinfo)
      .with(url.hostname, any_args)
      .and_return([addr])
  end

  def stubbed_hostname(url, hostname: IP_ADDRESS_STUB)
    url = URI(url)
    url.hostname = hostname
    url.to_s
  end
end
