PER_PAGE = 30
LIFE_TOKEN = 300
ALLOWED_IPS = [
  # Example: '192.168.1.10',
  # Add allowed IP addresses here
  '*'
]
PORT = 4567
IPBIND = '0.0.0.0'

if File.exist?('classes/config_custom.rb')
  orig_verbose = $VERBOSE
  $VERBOSE = nil
  require_relative 'config_custom'
  $VERBOSE = orig_verbose
end

LOCK_PATH = 'locks/lock'.freeze
GRANTED_UTILS = [
  'utils/config.sh',
  'utils/make_client_cert.sh',
  'utils/make_client_revoke.sh',
  'utils/make_server_cert.sh',
  'utils/make_server_revoke.sh',
  'utils/prepare.sh'
].freeze
