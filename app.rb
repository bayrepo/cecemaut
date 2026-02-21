# certcenter/app.rb

certsenter_ruby_gem_version = '3.3.0'
Gem.paths = {
  'GEM_HOME' => "#{__dir__}/vendor/bundle/ruby/#{certsenter_ruby_gem_version}",
  'GEM_PATH' => "#{__dir__}/vendor/bundle/ruby/#{certsenter_ruby_gem_version}"
}

require 'sinatra'
require 'sequel'
require 'sqlite3'
require 'securerandom'
require 'base64'
require 'jwt'
require 'openssl'

# --- i18n setup ---
require 'i18n'
require 'i18n/backend/fallbacks'
I18n.load_path += Dir[File.expand_path('locale/*.yml', __dir__)]
I18n.backend.load_translations
I18n::Backend::Simple.send(:include, I18n::Backend::Fallbacks)
I18n.default_locale = :en
I18n.enforce_available_locales = false
I18n.locale = ENV["LANG"].split("_").first.downcase.to_sym || :en
# -------------------

require_relative 'classes/config'

DB = Sequel.sqlite('db/base.sqlite')

require_relative 'models/users'
require_relative 'models/userdata'

require_relative 'classes/cert'
require_relative 'classes/pagination'

configure do
  Dir.mkdir('logs') unless Dir.exist?('logs')
  unless File.exist?('logs/actions.log')
    File.new('logs/actions.log', 'w').close
  end
  log_file = File.open('logs/actions.log', 'a+')
  STDOUT.reopen(log_file)
  STDERR.reopen(log_file)
  STDOUT.sync = true
  STDERR.sync = true
end

set :bind, IPBIND
set :port, PORT

signing_key_path = File.expand_path("../caapp.private.key.pem", __FILE__)
verify_key_path = File.expand_path("../caapp.public.key.pem", __FILE__)

signing_key = ""
verify_key = ""

File.open(signing_key_path) do |file|
  signing_key = OpenSSL::PKey.read(file)
end

File.open(verify_key_path) do |file|
  verify_key = OpenSSL::PKey.read(file)
end

set :signing_key, signing_key
set :verify_key, verify_key

enable :sessions
set :public_folder, File.dirname(__FILE__) + '/public'

configure do
  use Rack::Session::Pool, {
    expire_after: 86400,
  }
end

register do
  def auth(types)
    condition do
      unless send("is#{types}?")
        redirect '/login' if request.path == '/'
        redirect "/perms"
      end
    end
  end

  def authtok(types)
    condition do
      unless send("ist#{types}?")
        halt(403, { error: I18n.t('errors.no_permission'), content: nil }.to_json)
      end
    end
  end
end

helpers do
  def isuser?
    hasperms? 'user'
  end

  def iscreator?
    hasperms? 'creator'
  end

  def isadmin?
    hasperms? 'admin'
  end

  def hasperms?(level)
    return false if session[:user].nil?
    return true if level == 'admin' && session[:user].auth? && session[:user].role == 2
    return true if level == 'creator' && session[:user].auth? && [1, 2].include?(session[:user].role)
    return true if level == 'user' && session[:user].auth? && [0, 1, 2].include?(session[:user].role)

    false
  end

  def istuser?
    hastperms? 'user'
  end

  def istcreator?
    hastperms? 'creator'
  end

  def istadmin?
    hastperms? 'admin'
  end

  def hastperms?(level)
    return false if params[:token].nil?
    begin
      session_raw, headers = JWT.decode(params[:token], settings.verify_key, true, { algorithm: 'RS256'} )
      session_info = {}
      session_info["user"] = UserSessionData.deserialize(session_raw["user"])
    rescue JWT::DecodeError => e
      halt 401, { error: I18n.t('errors.authorization_error'), content: nil }.to_json
    end
    halt 401, { error: I18n.t('errors.token_expired'), content: nil }.to_json if headers["exp"] < Time.now.to_i
    @global_session = {}
    @global_session[:user] = session_info["user"]
    return false if session_info["user"].nil?
    return true if level == 'admin' && session_info["user"].auth? && session_info["user"].role == 2
    return true if level == 'creator' && session_info["user"].auth? && [1, 2].include?(session_info["user"].role)
    return true if level == 'user' && session_info["user"].auth? && [0, 1, 2].include?(session_info["user"].role)

    false
  end
end

before do
  lang = request.env['HTTP_ACCEPT_LANGUAGE']&.scan(/[a-z]{2}/)&.first || ENV["LANG"] || :en
  I18n.locale = lang.split("_").first.downcase.to_sym || :en
  if request.media_type == 'application/json'
    request.body.rewind
    body = request.body.read
    begin
      json_params = JSON.parse(body)
      params.merge!(json_params)
    rescue JSON::ParserError
      halt 400, { error: I18n.t('errors.invalid_json'), content: nil }.to_json
    end
  end
end

before do
  next if request.path == '/install'
  next if request.path.start_with?('/api/')
  unless File.exist?('utils/custom_config.sh')
    redirect '/install'
  end
end

before do
  allowed = ALLOWED_IPS
  if request.path.start_with?('/api/v1')
    halt 403, { error: I18n.t('errors.access_denied'), content: nil }.to_json unless allowed.include?(request.ip) || request.ip == '127.0.0.1' || request.ip == '::1' || allowed.include?("*")
  else
    unless allowed.include?(request.ip) || request.ip == '127.0.0.1' || request.ip == '::1' || allowed.include?("*")
      status 403
      @error = I18n.t('errors.access_denied')
      @log = nil
      erb :errinfo
      halt
    end
  end
end

# Главная страница
get '/' do
  if File.exist?('utils/custom_config.sh')
    redirect '/login' unless hasperms? 'user'
    @error = nil
    @log = nil
    @list_serv_full = []
    @tab = 0
    File.open(LOCK_PATH, File::RDWR | File::CREAT) do |f|
      mn = CertManager.new
      unless mn.error?
        @list_serv_full = mn.get_server_certs
        if mn.error?
          @error = mn.error
          @log = mn.log?
        else
          pg = Paginator.new(params, PER_PAGE)
          @list_serv = pg.get_page(@list_serv_full)
          @pages = pg.pages_info(@list_serv_full)
        end
      else
        @error = mn.error
        @log = mn.log?
      end
      f.flock(File::LOCK_UN)
    end
    @page_name = I18n.t('pages.servers')
    @menu = true
    if @error.nil?
      erb :list
    else
      erb :errinfo
    end

  else
    redirect '/install'
  end
end

get '/clients/?:id?', :auth => 'user' do
  @error = nil
  @log = nil
  @list_clients_full = []
  @list_servers_full = []
  @tab = 0
  server_cert = nil
  File.open(LOCK_PATH, File::RDWR | File::CREAT) do |f|
    mn = CertManager.new
    unless mn.error?
      @list_clients_full = mn.get_clients_certs('')
      if mn.error?
        @error = mn.error
        @log = mn.log?
      else
        pg = Paginator.new(params, PER_PAGE)
        @list_clients = pg.get_page(@list_clients_full)
        @pages = pg.pages_info(@list_clients_full)
        if params[:id]
          server_cert = mn.get_cert_info(params[:id])
          @error = mn.error
          @log = mn.log?
        end
      end
    else
      @error = mn.error
      @log = mn.log?
    end
    if @error.nil?
      @list_servers_full = mn.get_server_certs.map { |item| item[:ui][:CN] }.reject(&:empty?).uniq
    end
    f.flock(File::LOCK_UN)
  end
  if params[:id]
    @id = params[:id].to_i
    @tab = 1
    pg_c = Paginator.new(params, PER_PAGE, 'fp')
    if !server_cert.nil? && server_cert[:ui] && params[:id]
      cn = server_cert[:ui][:CN]
      @server_name = cn
      @list_clients_short = @list_clients_full.select { |entry| entry[:ui][:CN] == cn }
      @pages_short = pg_c.pages_info(@list_clients_short)
      @list_clients_full = @list_clients_short if params['cli'] == 'yes'
    end
  end

  @page_name = I18n.t('pages.clients')
  @menu = true
  if @error.nil?
    erb :listc
  else
    erb :errinfo
  end
end

get '/shows/:id', :auth => 'user' do
  @page_name = I18n.t('pages.servers')
  @cert_info = nil
  @tab = 1
  File.open(LOCK_PATH, File::RDWR | File::CREAT) do |f|
    mn = CertManager.new
    unless mn.error?
      @cert_info = mn.get_detail_cert_info(params[:id])
      if mn.error?
        @error = mn.error
        @log = mn.log?
      else
        @list_serv_full = mn.get_server_certs
        if mn.error?
          @error = mn.error
          @log = mn.log?
        else
          pg = Paginator.new(params, PER_PAGE)
          @list_serv = pg.get_page(@list_serv_full)
          @pages = pg.pages_info(@list_serv_full)
        end
      end
    else
      @error = mn.error
      @log = mn.log?
    end
    f.flock(File::LOCK_UN)
  end

  @menu = true
  if @error.nil?
    erb :list
  else
    erb :errinfo
  end
end

get '/showc/:id', :auth => 'user' do
  @page_name = I18n.t('pages.clients')
  @cert_info = nil
  @tab = 2
  @list_servers_full = []
  File.open(LOCK_PATH, File::RDWR | File::CREAT) do |f|
    mn = CertManager.new
    unless mn.error?
      @cert_info = mn.get_detail_cert_info(params[:id])
      if mn.error?
        @error = mn.error
        @log = mn.log?
      else
        @list_clients_full = mn.get_clients_certs('')
        if mn.error?
          @error = mn.error
          @log = mn.log?
        else
          pg = Paginator.new(params, PER_PAGE)
          @list_clients = pg.get_page(@list_clients_full)
          @pages = pg.pages_info(@list_clients_full)
        end
      end
    else
      @error = mn.error
      @log = mn.log?
    end
    if @error.nil?
      @list_servers_full = mn.get_server_certs.map { |item| item[:ui][:CN] }.reject(&:empty?).uniq
    end
    f.flock(File::LOCK_UN)
  end

  @page_name = I18n.t('pages.clients')
  @menu = true
  if @error.nil?
    erb :listc
  else
    erb :errinfo
  end

end

get '/revoke/:id', :auth => 'creator' do
  @page_name = I18n.t('pages.revocation')
  begin
    if params[:id].nil? || params[:id].strip == ''
      @error = I18n.t('errors.revocation_missing_id')
      @log = ""
      raise ArgumentError
    end
    File.open(LOCK_PATH, File::RDWR | File::CREAT) do |f|
      mn = CertManager.new
      unless mn.error?
        @cert_info = mn.revoke_certificat(params[:id])
        if mn.error?
          @error = mn.error
          @log = mn.log?
        else
          if @cert_info.nil?
            @error = I18n.t('errors.revocation_failed')
            @log = mn.log?
          end
        end
      else
        @error = mn.error
        @log = mn.log?
      end
      f.flock(File::LOCK_UN)
    end
  rescue ArgumentError
    #Nothing to do
  end

  if @error.nil?
    if @cert_info[:is_client]
      redirect "/showc/#{@cert_info[:id]}"
    else
      redirect "/shows/#{@cert_info[:id]}"
    end
  else
    erb :errinfo
  end

end

post '/addclient', :auth => 'creator' do
  @page_name = I18n.t('pages.clients')
  begin
    if params['server_domain'].nil? || params['server_domain'].strip == ''
      @error = I18n.t('errors.server_domain_missing')
      @log = ""
      raise ArgumentError
    end
    if params['client'].nil? || params['client'].strip == ''
      @error = I18n.t('errors.client_id_missing')
      @log = ""
      raise ArgumentError
    end
    if params['validity_days'].nil? || params['validity_days'].to_i < 1
      @error = I18n.t('errors.validity_days_missing')
      @log = ""
      raise ArgumentError
    end
    File.open(LOCK_PATH, File::RDWR | File::CREAT) do |f|
      mn = CertManager.new
      unless mn.error?
        @cert_info = mn.add_client_cert(params['server_domain'], params['client'], params['validity_days'])
        if mn.error?
          @error = mn.error
          @log = mn.log?
        else
          if @cert_info.nil?
            @error = I18n.t('errors.cert_created_error')
            @log = mn.log?
          end
        end
      else
        @error = mn.error
        @log = mn.log?
      end
      f.flock(File::LOCK_UN)
    end
  rescue ArgumentError
    #Nothing to do
  end

  if @error.nil?
    redirect "/showc/#{@cert_info[:id]}"
  else
    erb :errinfo
  end
end

post '/addserver', :auth => 'creator' do
  @page_name = I18n.t('pages.servers')
  begin
    if params['domains'].nil? || params['domains'].strip == ''
      @error = I18n.t('errors.domains_missing')
      @log = ""
      raise ArgumentError
    end
    if params['validity_days'].nil? || params['validity_days'].to_i < 1
      @error = I18n.t('errors.validity_days_missing')
      @log = ""
      raise ArgumentError
    end
    File.open(LOCK_PATH, File::RDWR | File::CREAT) do |f|
      mn = CertManager.new
      unless mn.error?
        @cert_info = mn.add_cert(params['validity_days'], params['domains'])
        if mn.error?
          @error = mn.error
          @log = mn.log?
        else
          if @cert_info.nil?
            @error = I18n.t('errors.cert_created_error')
            @log = mn.log?
          end
        end
      else
        @error = mn.error
        @log = mn.log?
      end
      f.flock(File::LOCK_UN)
    end
  rescue ArgumentError
    #Nothing to do
  end

  if @error.nil?
    redirect "/shows/#{@cert_info[:id]}"
  else
    erb :errinfo
  end
end

get '/download/:id' ,:auth => 'creator' do
  binary_data = nil
  File.open(LOCK_PATH, File::RDWR | File::CREAT) do |f|
    mn = CertManager.new
    unless mn.error?
      binary_data = mn.get_cert_binary(params[:id])
      if binary_data.nil?
        @error = mn.error
        @log = mn.log?
      end
    else
      @error = mn.error
      @log = mn.log?
    end
    f.flock(File::LOCK_UN)
  end

  if @error.nil?
    content_type 'application/octet-stream'
    attachment('keys.zip')
    binary_data[:zip]
  else
    erb :errinfo
  end

end

get '/ulist' ,:auth => 'admin' do
  @menu = true
  @page_name = I18n.t('pages.users')
  @tab = 0
  @users = session[:user].list_users
  @pages = Paginator.new(params, PER_PAGE).pages_info(@users)

  erb :ulist

end

get '/deleteuser/:id', :auth => 'admin' do
    user_id = params[:id]
    result = session[:user].del_user(nil, user_id)

    if result.nil? || result[:error].nil?
      redirect '/ulist'
    else
      @error = result[:error]
      erb :errinfo
    end
end

post '/adduser', :auth => 'admin' do
  name = params[:login]
  password = params[:password]
  email = params[:email] || ''
  role = params[:role]

  if name.nil? || name.strip == '' || password.nil? || password.strip == '' || role.nil?
    @error = 'All fields are required'
    erb :errinfo
  else
    session[:user].add_user(name, password, email, role)
    if session[:user].err
      @error = session[:user].err
      erb :errinfo
    else
      redirect '/ulist'
    end
  end
end

get '/edituser/:id', :auth => 'admin' do
  @page_name = I18n.t('pages.users')
  user_id = params[:id]
  @selected_user = session[:user].user_info(nil, user_id)

  if @selected_user.nil?
    @error = I18n.t('errors.user_not_found')
    erb :errinfo
  else
    @menu = true
    @tab = 1
    @users = session[:user].list_users
    @pages = Paginator.new(params, PER_PAGE).pages_info(@users)
    erb :ulist
  end
end

post '/edituser/:id', :auth => 'admin' do
  @selected_user = session[:user].user_info(nil, params[:id])

  if @selected_user.nil?
    @error = I18n.t('errors.user_not_found')
    erb :errinfo
  else
    name = params[:login]
    password = params[:password]
    role = params[:role]
    id = params[:id]
    email = params[:email]

    if name.nil? || name.strip == '' || role.nil?
      @error = 'All fields are required'
      erb :errinfo
    else
      session[:user].update_user(name, password, email, role, id)
      if session[:user].err
        @error = session[:user].err
        erb :errinfo
      else
        redirect '/ulist'
      end
    end
  end
end

get '/login' do
  redirect '/' if hasperms?('user')
  @page_name = I18n.t('pages.login')
  erb :login
end

post '/login' do
  @page_name = I18n.t('pages.login')
  name = params[:login]
  password = params[:password]
  user_session = UserSessionData.new(name, password)

  if user_session.auth?
    session[:user] = user_session
    redirect '/'
  else
    @error = I18n.t('errors.invalid_username_password')
    erb :login
  end
end

get '/logout' do
  session[:user] = nil

  redirect '/'
end

get '/install' do
  @page_name = I18n.t('pages.install_server')
  if File.exist?('utils/custom_config.sh')
    @reason = I18n.t('messages.install_not_possible')
    @info_descr = I18n.t('messages.install_detected')
    erb :info
  elsif GRANTED_UTILS.any? { |util| !File.exist?(util) }
    @reason = I18n.t('messages.install_not_possible')
    @info_descr = I18n.t('messages.missing_utilities', missing: GRANTED_UTILS.reject { |util| File.exist?(util) }.join(', '))
    erb :info
  else
    erb :config
  end
end

post '/install' do
  File.open(LOCK_PATH, File::RDWR | File::CREAT) do |f|
    result = f.flock(File::LOCK_EX | File::LOCK_NB)
    @page_name = I18n.t('pages.install_server')
    if File.exist?('utils/custom_config.sh')
      f.flock(File::LOCK_UN)
      @reason = I18n.t('messages.install_not_possible')
      @info_descr = I18n.t('messages.install_detected')
      erb :info
    elsif GRANTED_UTILS.any? { |util| !File.exist?(util) }
      f.flock(File::LOCK_UN)
      @reason = I18n.t('messages.install_not_possible')
      @info_descr = I18n.t('messages.missing_utilities', missing: GRANTED_UTILS.reject { |util| File.exist?(util) }.join(', '))
      erb :info
      halt
    end

    cert_path = params['cert-path']
    org_name = params['org-name']
    common_name = params['common-name']
    cert_password = params['cert-password']
    country_name = params['country-name']
    validity_days = params['validity-days']

    cert_path = File.expand_path(cert_path) unless cert_path.start_with?('/')

    if !(cert_path.strip.empty? && org_name.strip.empty? && common_name.strip.empty? && cert_password.strip.empty? && country_name.strip.empty? && validity_days.strip.empty?)
      if File.directory?(cert_path) && !cert_path.start_with?('/etc')
        File.open('utils/custom_config.sh', 'w') do |file|
          file.puts %(ROOT_DIR="#{cert_path}")
          file.puts %(COUNTRY_NAME="#{country_name}")
          file.puts %(ORG_NAME="#{org_name}")
          file.puts %(COMM_NAME="#{common_name}")
          file.puts %(SERT_PASS="#{cert_password}")
          file.puts %(VAL_DAYS="#{validity_days}")
        end
        result_status = 0
        result_error = ''
        Dir.chdir('utils') do
          result = `bash ./prepare.sh`
          result_status = $?.exitstatus
          if result_status != 0
            result_error = result.strip
            Dir.chdir('../..')
          end
        end
        f.flock(File::LOCK_UN)
        if result_status != 0
          @reason = I18n.t('messages.install_failed', cert_path: cert_path)
          @info_descr = result_error
        else
          @reason = I18n.t('messages.install_success')
          @info_descr = I18n.t('messages.install_success_descr')
        end
        erb :info
      end
    else
      f.flock(File::LOCK_UN)
      @reason = I18n.t('messages.install_not_possible')
      @info_descr = I18n.t('messages.install_incomplete')
      erb :info
    end
  end
end

get '/perms' do
  status 403
  @reason = I18n.t('messages.install_failed', cert_path: cert_path)
  @info_descr = 'Авторизируйтесь или обратитесь к администратору для повышения своих прав.'
  erb :perms
end

get '/apiinfo', :auth => 'user' do
  @page_name = I18n.t('pages.api')
  @menu = true
  erb :api
end

get '/root', :auth => 'user' do
  @page_name = I18n.t('pages.root')
  @menu = true
  File.open(LOCK_PATH, File::RDWR | File::CREAT) do |f|
    mn = CertManager.new
    unless mn.error?
      @cert_info = mn.get_root_info
      if !mn.error.nil?
        @error = mn.error
        @log = mn.log?
      end
    else
      @error = mn.error
      @log = mn.log?
    end
    f.flock(File::LOCK_UN)
  end
  if @error.nil?
    erb :root
  else
    erb :errinfo
  end
end

not_found do
  request_path = env['REQUEST_PATH']

  status 404
  if request_path.start_with?('/api/v1')
    content_type 'application/json'
    { error: I18n.t('errors.page_not_found'), content: nil }.to_json
  else
    @page_name = I18n.t('pages.not_found')
    @reason = I18n.t('pages.not_found')
    @info_descr = I18n.t('pages.not_found')
    erb :info
  end
end

# API v1

post '/api/v1/login' do
  login = params[:login]
  password = params[:password]

  if login.nil? || login.strip == '' || password.nil? || password.strip == ''
    { error: I18n.t('errors.invalid_username_password'), content: nil }.to_json
  else
    user_session = UserSessionData.new(login, password)
    if user_session.auth?
      headers = {
        exp: Time.now.to_i + LIFE_TOKEN
      }
      token = JWT.encode({ user: user_session.serialize }, settings.signing_key, 'RS256', headers)
      { error: nil, content: { token: token } }.to_json
    else
      { error: I18n.t('errors.invalid_username_password'), content: nil }.to_json
    end
  end
end

post '/api/v1/servers', :authtok => 'user' do
  @error = nil
  @log = nil
  @list_serv_full = []
  File.open(LOCK_PATH, File::RDWR | File::CREAT) do |f|
    mn = CertManager.new
    unless mn.error?
      @list_serv_full = mn.get_server_certs
      if mn.error?
        @error = mn.error
        @log = mn.log?
      end
    else
      @error = mn.error
      @log = mn.log?
    end
    f.flock(File::LOCK_UN)
  end
  content_type :json
  if @error.nil?
    { error: nil, content: @list_serv_full }.to_json
  else
    { error: @error, content: @log }.to_json
  end
end

post '/api/v1/clients', :authtok => 'user' do
  @error = nil
  @log = nil
  @list_clients_full = []
  File.open(LOCK_PATH, File::RDWR | File::CREAT) do |f|
    mn = CertManager.new
    unless mn.error?
      @list_clients_full = mn.get_clients_certs('')
      if mn.error?
        @error = mn.error
        @log = mn.log?
      end
    else
      @error = mn.error
      @log = mn.log?
    end
    f.flock(File::LOCK_UN)
  end
  content_type :json
  if @error.nil?
    { error: nil, content: @list_clients_full }.to_json
  else
    { error: @error, content: @log }.to_json
  end
end

post '/api/v1/certinfo/:id', :authtok => 'user' do
  @error = nil
  @log = nil
  @list_clients_full = []
  File.open(LOCK_PATH, File::RDWR | File::CREAT) do |f|
    mn = CertManager.new
    unless mn.error?
      @cert_info = mn.get_detail_cert_info(params[:id])
      if mn.error?
        @error = mn.error
        @log = mn.log?
      end
    else
      @error = mn.error
      @log = mn.log?
    end
    f.flock(File::LOCK_UN)
  end
  content_type :json
  if @error.nil?
    { error: nil, content: @cert_info }.to_json
  else
    { error: @error, content: @log }.to_json
  end
end

post '/api/v1/root', :authtok => 'user' do
  @error = nil
  @log = nil
  @cert_info = nil
  File.open(LOCK_PATH, File::RDWR | File::CREAT) do |f|
    mn = CertManager.new
    unless mn.error?
      @cert_info = mn.get_root_info
      if mn.error?
        @error = mn.error
        @log = mn.log?
      end
    else
      @error = mn.error
      @log = mn.log?
    end
    f.flock(File::LOCK_UN)
  end
  content_type :json
  if @error.nil?
    { error: nil, content: @cert_info }.to_json
  else
    { error: @error, content: @log }.to_json
  end
end

post '/api/v1/revoke/:id', :authtok => 'creator' do
  @error = nil
  @log = nil
  @list_clients_full = []
  File.open(LOCK_PATH, File::RDWR | File::CREAT) do |f|
    mn = CertManager.new
    unless mn.error?
      @cert_info = mn.revoke_certificat(params[:id])
      if mn.error?
        @error = mn.error
        @log = mn.log?
      end
    else
      @error = mn.error
      @log = mn.log?
    end
    f.flock(File::LOCK_UN)
  end
  content_type :json
  if @error.nil?
    { error: nil, content: @cert_info }.to_json
  else
    { error: @error, content: @log }.to_json
  end
end

post '/api/v1/addclient', :authtok => 'creator' do
  @log = nil
  @error = nil
  begin
    if params['server_domain'].nil? || params['server_domain'].strip == ''
      @error = I18n.t('errors.server_domain_missing')
      @log = ""
      raise ArgumentError
    end
    if params['client'].nil? || params['client'].strip == ''
      @error = I18n.t('errors.client_id_missing')
      @log = ""
      raise ArgumentError
    end
    if params['validity_days'].nil? || params['validity_days'].to_i < 1
      @error = I18n.t('errors.validity_days_missing')
      @log = ""
      raise ArgumentError
    end
    File.open(LOCK_PATH, File::RDWR | File::CREAT) do |f|
      mn = CertManager.new
      unless mn.error?
        @cert_info = mn.add_client_cert(params['server_domain'], params['client'], params['validity_days'])
        if mn.error?
          @error = mn.error
          @log = mn.log?
        else
          if @cert_info.nil?
            @error = I18n.t('errors.cert_created_error')
            @log = mn.log?
          end
        end
      else
        @error = mn.error
        @log = mn.log?
      end
      f.flock(File::LOCK_UN)
    end
  rescue ArgumentError
    #Nothing to do
  end

  content_type :json
  if @error.nil?
    { error: nil, content: @cert_info }.to_json
  else
    { error: @error, content: @log }.to_json
  end
end

post '/api/v1/addserver', :authtok => 'creator' do
  @log = nil
  @error = nil
  begin
    if params['domains'].nil? || params['domains'].strip == ''
      @error = I18n.t('errors.domains_missing')
      @log = ""
      raise ArgumentError
    end
    if params['validity_days'].nil? || params['validity_days'].to_i < 1
      @error = I18n.t('errors.validity_days_missing')
      @log = ""
      raise ArgumentError
    end
    File.open(LOCK_PATH, File::RDWR | File::CREAT) do |f|
      mn = CertManager.new
      unless mn.error?
        @cert_info = mn.add_cert(params['validity_days'], params['domains'])
        if mn.error?
          @error = mn.error
          @log = mn.log?
        else
          if @cert_info.nil?
            @error = I18n.t('errors.cert_created_error')
            @log = mn.log?
          end
        end
      else
        @error = mn.error
        @log = mn.log?
      end
      f.flock(File::LOCK_UN)
    end
  rescue ArgumentError
    #Nothing to do
  end

  content_type :json
  if @error.nil?
    { error: nil, content: @cert_info }.to_json
  else
    { error: @error, content: @log }.to_json
  end
end

post '/api/v1/download/:id' ,:auth => 'creator' do
  @log = nil
  @error = nil
  binary_data = nil
  File.open(LOCK_PATH, File::RDWR | File::CREAT) do |f|
    mn = CertManager.new
    unless mn.error?
      binary_data = mn.get_cert_binary(params[:id])
      if binary_data.nil?
        @error = mn.error
        @log = mn.log?
      end
    else
      @error = mn.error
      @log = mn.log?
    end
    f.flock(File::LOCK_UN)
  end

  content_type :json
  if @error.nil?
    { error: nil, content: Base64.encode64(binary_data) }.to_json
  else
    { error: @error, content: @log }.to_json
  end

end

post '/api/v1/ulist' ,:authtok => 'admin' do
  @log = nil
  @users = @global_session[:user].list_users
  @error = @global_session[:user].err

  content_type :json
  if @error.nil?
    { error: nil, content: @users.map{ |item| item.to_hash } }.to_json
  else
    { error: @error, content: @log }.to_json
  end

end

post '/api/v1/deleteuser/:id', :authtok => 'admin' do
    @log = nil
    user_id = params[:id]
    result = @global_session[:user].del_user(nil, user_id)
    @error = @global_session[:user].err

    content_type :json
    if result.nil? || result[:error].nil?
      { error: nil, content: I18n.t('messages.user_deleted') }.to_json
    else
      { error: @error, content: @log }.to_json
    end
end

post '/api/v1/adduser', :authtok => 'admin' do
  @log = nil
  @error = nil
  name = params[:login]
  password = params[:password]
  email = params[:email] || ''
  role = params[:role]

  if name.nil? || name.strip == '' || password.nil? || password.strip == '' || role.nil?
    @error = I18n.t('errors.all_fields_required')
  end

  @global_session[:user].add_user(name, password, email, role) if @error.nil?
  @error = @global_session[:user].err

  content_type :json
  if @error.nil?
    { error: nil, content: I18n.t('messages.user_added') }.to_json
  else
    { error: @error, content: @log }.to_json
  end
end

post '/api/v1/edituser/:id', :authtok => 'admin' do
  @log = nil
  @error = nil
  @selected_user = @global_session[:user].user_info(nil, params[:id])

  if @selected_user.nil?
    @error = I18n.t('errors.user_not_found')
  else
    name = params[:login]
    password = params[:password]
    role = params[:role]
    id = params[:id]
    email = params[:email]

    if name.nil? || name.strip == '' || role.nil?
      @error = I18n.t('errors.all_fields_required')
    else
      @global_session[:user].update_user(name, password, email, role, id)
      @error = @global_session[:user].err
    end
  end

  content_type :json
  if @error.nil?
    { error: nil, content: I18n.t('messages.user_added') }.to_json
  else
    { error: @error, content: @log }.to_json
  end
end

post '/api/v1/install' do
  File.open(LOCK_PATH, File::RDWR | File::CREAT) do |f|
    result = f.flock(File::LOCK_EX | File::LOCK_NB)
    if File.exist?('utils/custom_config.sh')
      f.flock(File::LOCK_UN)
      @reason = I18n.t('messages.install_not_possible')
      @info_descr = I18n.t('messages.install_detected')
      content_type :json
      { error: @reason, content: @info_descr }.to_json
      halt 503
    elsif GRANTED_UTILS.any? { |util| !File.exist?(util) }
      f.flock(File::LOCK_UN)
      @reason = I18n.t('messages.install_not_possible')
      @info_descr = I18n.t('messages.missing_utilities', missing: GRANTED_UTILS.reject { |util| File.exist?(util) }.join(', '))
      content_type :json
      { error: @reason, content: @info_descr }.to_json
      halt 503
    end

    cert_path = params['cert-path']
    org_name = params['org-name']
    common_name = params['common-name']
    cert_password = params['cert-password']
    country_name = params['country-name']
    validity_days = params['validity-days']

    cert_path = File.expand_path(cert_path) unless cert_path.start_with?('/')

    if !(cert_path.strip.empty? && org_name.strip.empty? && common_name.strip.empty? && cert_password.strip.empty? && country_name.strip.empty? && validity_days.strip.empty?)
      if File.directory?(cert_path) && !cert_path.start_with?('/etc')
        File.open('utils/custom_config.sh', 'w') do |file|
          file.puts %(ROOT_DIR="#{cert_path}")
          file.puts %(COUNTRY_NAME="#{country_name}")
          file.puts %(ORG_NAME="#{org_name}")
          file.puts %(COMM_NAME="#{common_name}")
          file.puts %(SERT_PASS="#{cert_password}")
          file.puts %(VAL_DAYS="#{validity_days}")
        end
        result_status = 0
        result_error = ''
        Dir.chdir('utils') do
          result = `bash ./prepare.sh`
          result_status = $?.exitstatus
          if result_status != 0
            result_error = result.strip
            Dir.chdir('../..')
          end
        end
        f.flock(File::LOCK_UN)
        if result_status != 0
          content_type :json
          halt(200, { content: '', error: result_error }.to_json)
        else
          content_type :json
          halt(200, { content: I18n.t('messages.install_success'), error: '' }.to_json)
        end
      end
    else
      f.flock(File::LOCK_UN)
      @reason = I18n.t('messages.install_not_possible')
      @info_descr = I18n.t('messages.install_incomplete')
      content_type :json
      { error: @reason, content: @info_descr }.to_json
      halt 503
    end
  end
end
