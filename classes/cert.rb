require 'date'
require 'zip'
require 'i18n'
require_relative 'runner'

class CertManager
  attr_accessor :error, :log, :root_ca

  def initialize()
    @root_ca = gt_root_dir
    if @root_ca.nil?
      @error = I18n.t('errors.cannot_determine_root_dir')
    end
  end

  def log?
    @log
  end

  def rootca?
    @root_ca
  end

  def error?
    !(@error.nil? || @error.strip == '')
  end

  def add_cert(days, domains_ips_list)
    begin
      @error = nil
      @log = nil
      new_cert_info = nil
      days = begin
        Integer(days)
      rescue StandardError
        nil
      end
      raise ArgumentError, I18n.t('errors.argument_error_days') if days.nil? || days <= 0

      domains_ips = domains_ips_list.split(/[\s,]+/).reject(&:empty?).uniq
      raise ArgumentError, I18n.t('errors.argument_error_domains_ips') if domains_ips.empty?

      result = ''
      current_directory = Dir.pwd
      Dir.chdir('utils') do
        cmd_args = %Q(bash ./make_server_cert.sh -t #{days} #{domains_ips.join(' ')} 2>&1)
        cmd = Runner.new(cmd_args)
        cmd.run_clean
        result = cmd.stdout
        raise StandardError, I18n.t('errors.command_execution_error', command: cmd_args) if cmd.exit_status != 0
        result.each_line do |line|
          if line =~ /\[OUTPUTDATA_CERT\]/
            match = line.match(/([^\/]*?)\.cert\.pem\.(\d+)/)
            if match
              new_cert_info = { name: match[1], seq: match[2] }
              break
            end
          end
        end
        raise StandardError, I18n.t('errors.no_result_file') if new_cert_info.nil?
      end
    rescue ArgumentError => e
      @error = e.message
    rescue StandardError => e
      @error = e.message
      @log = result
      Dir.chdir(current_directory)
    ensure
    end
    @log = result
    if new_cert_info.nil?
      nil
    else
      get_cert_id_by_name(domains_ips[0], new_cert_info[:seq], new_cert_info[:name], 's')
    end
  end

  def add_client_cert(server_domain, client_id, days)
    begin
      @error = nil
      @log = nil
      new_cert_info = nil
      raise ArgumentError, I18n.t('errors.argument_error_server_domain') if server_domain.strip.empty?
      raise ArgumentError, I18n.t('errors.argument_error_client_id') if client_id.strip.empty?

      days = begin
        Integer(days)
      rescue StandardError
        nil
      end
      raise ArgumentError, I18n.t('errors.argument_error_days') if days.nil? || days <= 0

      @error = nil
      result = ''
      current_directory = Dir.pwd
      Dir.chdir('utils') do
        cmd_args = %Q(bash ./make_client_cert.sh -s #{server_domain} -c #{client_id} -d #{days} 2>&1)
        cmd = Runner.new(cmd_args)
        cmd.run_clean
        result = cmd.stdout
        raise StandardError, I18n.t('errors.command_execution_error', command: cmd_args) if cmd.exit_status != 0
        result.each_line do |line|
          if line =~ /\[OUTPUTDATA_CERT\]/
            match = line.match(/([^\/]*?)\.cert\.pem\.(\d+)/)
            if match
              new_cert_info = { name: match[1], seq: match[2] }
              break
            end
          end
        end
        raise StandardError, I18n.t('errors.no_result_file') if new_cert_info.nil?
      end
    rescue ArgumentError => e
      @error = e.message
    rescue StandardError => e
      @error = e.message
      Dir.chdir(current_directory)
    ensure
    end
    @log = result
    if new_cert_info.nil?
      nil
    else
      get_cert_id_by_name(server_domain, new_cert_info[:seq], new_cert_info[:name], 'c')
    end
  end

  def get_server_certs
    get_list_certs('s')
  end

  def get_clients_certs(server_domain)
    list = get_list_certs('c')
    if server_domain == ''
      list
    else
      filtered_list = list.select { |entry| entry[:ui][:CN] == server_domain }
      filtered_list.sort_by! { |entry| entry[:id] }
    end
  end

  def get_cert_info(id)
    @log = ""
    @error = nil
    list_certs = get_list_certs('*')
    target_id = id
    found_entry = list_certs.find do |entry|
      entry[:id] == target_id
    end
    if found_entry
      return found_entry
    else
      @error = I18n.t('errors.record_not_found')
      return nil
    end
  end

  def get_detail_cert_info(id)
    @log = nil
    @error = nil
    cert_info = { common: nil, revoke: nil, is_client: nil, name: nil, id: id, full: nil }

    if @root_ca.nil?
      @error = I18n.t('errors.root_ca_not_detected')
      return cert_info
    end

    cert_item_data = get_cert_info(id)

    if !@error.nil? || cert_item_data.nil?
      return cert_info
    end

    cert_item = get_cert_path(cert_item_data)
    cert_path = if cert_item[:is_client]
      cert_item[:client]
    else
      cert_item[:server]
    end

    files_list = []
    readme_txt = ""
    if cert_item[:is_client]
      files_list << cert_item[:client]
      files_list << "#{@root_ca}/ca/client_certs/#{cert_item[:server_name]}/private/#{cert_item[:client_id]}_private.key.pem"
      files_list << "#{@root_ca}/ca/intermediate/certs/ca-chain.cert.pem"
      readme_txt = I18n.t('messages.client_readme', private_key: files_list[1], server_cert: files_list[0], ca_chain: files_list[2])
    else
      files_list << cert_item[:server]
      files_list << "#{@root_ca}/ca/intermediate/private/#{cert_item[:server_name]}.key.pem"
      files_list << "#{@root_ca}/ca/intermediate/certs/ca-chain.cert.pem"
      files_list << "#{@root_ca}/ca/intermediate/crl/ca-full.crl.pem"
      readme_txt = I18n.t('messages.server_readme', private_key: files_list[1], server_cert: files_list[0], ca_chain: files_list[2], crl: files_list[3])
    end
    cert_info[:full] = readme_txt

    unless File.exist?(cert_path)
      @error = I18n.t('errors.root_ca_not_detected')
      return cert_info
    end

    cmd_args = %Q(openssl x509 -in "#{cert_path}" -text -noout 2>&1)
    cmd = Runner.new(cmd_args)
    cmd.run_clean
    if cmd.exit_status != 0
      @error = I18n.t('errors.cannot_get_certificate_info')
      @log = cmd.stdout
      return cert_info
    end

    cert_info[:common] = cmd.stdout

    cmd_args = %Q(openssl verify -crl_check_all -CAfile "#{@root_ca}/ca/intermediate/certs/ca-chain.cert.pem" -CRLfile "#{@root_ca}/ca/intermediate/crl/ca-full.crl.pem" "#{cert_path}" 2>&1)
    cmd = Runner.new(cmd_args)
    cmd.run_clean
    cert_info[:revoke] = cmd.stdout
    cert_info[:name] = "/#{cert_item_data[:ui][:O]}/#{cert_item_data[:ui][:CN]}/"

    cert_info
  end

  def revoke_certificat(id)
    @error = nil
    @log = nil
    cert_info = get_cert_info(id)
    if cert_info.nil?
      nil
    else
      cert_data = get_cert_path(cert_info)
      if cert_data[:is_client]
        revoke_client_cert(cert_data[:server_name], cert_data[:client_id], cert_data[:seq])
      else
        revoke_cert(cert_data[:server_name], cert_data[:seq])
      end
      if @error.nil?
        cert_info = get_cert_info(id)
        if cert_info.nil?
          nil
        else
          cert_info[:is_client] = cert_data[:is_client]
          cert_info
        end
      else
        nil
      end
    end
  end

  def get_cert_binary(id)
    @error = nil
    @log = nil
    files_list = []
    readme_txt = ""
    cert_data = get_cert_info(id)
    if cert_data.nil?
      nil
    else
      cert_path = get_cert_path(cert_data)
      if cert_path[:is_client]
        files_list << cert_path[:client]
        files_list << "#{@root_ca}/ca/client_certs/#{cert_path[:server_name]}/private/#{cert_path[:client_id]}_private.key.pem"
        files_list << "#{@root_ca}/ca/intermediate/certs/ca-chain.cert.pem"
        readme_txt = I18n.t('messages.client_readme', private_key: File.basename(files_list[1]), server_cert: File.basename(files_list[0]), ca_chain: File.basename(files_list[2]))
      else
        files_list << cert_path[:server]
        files_list << "#{@root_ca}/ca/intermediate/private/#{cert_path[:server_name]}.key.pem"
        files_list << "#{@root_ca}/ca/intermediate/certs/ca-chain.cert.pem"
        files_list << "#{@root_ca}/ca/intermediate/crl/ca-full.crl.pem"
        readme_txt = I18n.t('messages.server_readme', private_key: File.basename(files_list[1]), server_cert: File.basename(files_list[0]), ca_chain: File.basename(files_list[2]), crl: File.basename(files_list[3]))
      end
      if files_list.all? { |file| File.exist?(file) }
        zip_memory = Zip::OutputStream.write_buffer do |zos|
          files_list.each do |file|
            zos.put_next_entry(File.basename(file))
            File.open(file, 'rb') { |f| zos.write f.read }
          end
          text_entry_name = 'readme.txt'
          zos.put_next_entry(text_entry_name)
          zos.write readme_txt
        end
        { zip: zip_memory.string, is_client: cert_path[:is_client] }
      else
        @error = I18n.t('errors.root_ca_not_detected')
        return nil
      end
    end
  end

  def get_root_info
    @log = nil
    @error = nil
    cert_info = { common: nil, revoke: nil, is_client: nil, name: nil, id: nil }

    if @root_ca.nil?
      @error = I18n.t('errors.root_ca_not_detected')
      return cert_info
    end

    org_nm = nil
    config_sh = File.read('utils/custom_config.sh')
    match = config_sh.match(/ORG_NAME="([^"]+)"/)
    org_nm = match[1] if match
    return nil if org_nm.nil?

    cert_path = "#{root_ca}/ca/root/certs/ca.cert.pem"

    unless File.exist?(cert_path)
      @error = I18n.t('errors.root_ca_not_detected')
      return cert_info
    end

    cmd_args = %Q(openssl x509 -in "#{cert_path}" -text -noout 2>&1)
    cmd = Runner.new(cmd_args)
    cmd.run_clean
    if cmd.exit_status != 0
      @error = I18n.t('errors.cannot_get_certificate_info')
      @log = cmd.stdout
      return cert_info
    end

    cert_info[:common] = cmd.stdout

    cmd_args = %Q(openssl verify -crl_check_all -CAfile "#{cert_path}" -CRLfile "#{@root_ca}/ca/root/crl/ca.crl.pem" "#{cert_path}" 2>&1)
    cmd = Runner.new(cmd_args)
    cmd.run_clean
    cert_info[:revoke] = cmd.stdout
    cert_info[:name] = "/CN=#{org_nm}/"

    cert_info
  end

  private

  def revoke_cert(server_domain, seq)
    current_dir = Dir.pwd
    begin
      @log = nil
      raise ArgumentError, I18n.t('errors.argument_error_server_domain') if server_domain.strip.empty?

      @error = nil
      result = ''
      Dir.chdir('utils') do
        cmd_args = if seq.nil? || seq.empty?
          %Q(bash ./make_server_revoke.sh -s #{server_domain} 2>&1)
        else
          %Q(bash ./make_server_revoke.sh -n #{seq} -s #{server_domain} 2>&1)
        end
        cmd = Runner.new(cmd_args)
        cmd.run_clean
        result = cmd.stdout
        raise StandardError, I18n.t('errors.command_execution_error', command: cmd_args) if cmd.exit_status != 0
      end
    rescue ArgumentError => e
      @error = e.message
    rescue StandardError => e
      @error = e.message
      Dir.chdir(current_dir)
    ensure
    end
    @log = result
  end

  def revoke_client_cert(server_domain, client_id, seq)
    current_dir = Dir.pwd
    begin
      @log = nil
      raise ArgumentError, I18n.t('errors.argument_error_server_domain') if server_domain.strip.empty?
      raise ArgumentError, I18n.t('errors.argument_error_client_id') if client_id.strip.empty?

      @error = nil
      result = ''
      Dir.chdir('utils') do
        cmd_args = if seq.nil? || seq.empty?
          %Q(bash ./make_client_revoke.sh -s #{server_domain} -c #{client_id} 2>&1)
        else
          %Q(bash ./make_client_revoke.sh -s #{server_domain} -c #{client_id} -n #{seq} 2>&1)
        end
        cmd = Runner.new(cmd_args)
        cmd.run_clean
        result = cmd.stdout
        raise StandardError, I18n.t('errors.command_execution_error', command: cmd_args) if cmd.exit_status != 0
      end
    rescue ArgumentError => e
      @error = e.message
    rescue StandardError => e
      @error = e.message
      Dir.chdir(current_dir)
    ensure
    end
    @log = result
  end

  def gt_root_dir
    root_ca = nil

    config_sh = File.read('utils/custom_config.sh')
    match = config_sh.match(/ROOT_DIR="([^"]+)"/)
    root_ca = match[1] if match
    root_ca
  end

  def get_cert_path(item)
    cl_name = item[:ui][:O].split(":")
    cert_file = if cl_name.length > 1
      "#{@root_ca}/ca/client_certs/#{item[:ui][:CN]}/#{cl_name[0]}.cert.pem.#{cl_name[1]}"
    else
      "#{@root_ca}/ca/client_certs/#{item[:ui][:CN]}/#{cl_name[0]}.cert.pem"
    end
    sr_name = item[:ui][:CN]
    serv_file = if cl_name.length > 1
      "#{@root_ca}/ca/intermediate/certs/#{sr_name}.cert.pem.#{cl_name[1]}"
    else
      "#{@root_ca}/ca/intermediate/certs/#{sr_name}.cert.pem"
    end
    is_client = File.exist?(cert_file)
    seq = if cl_name.length > 1
      cl_name[1]
    else
      nil
    end
    { client: cert_file, server: serv_file, is_client: is_client, server_name: sr_name, seq: seq, client_id: cl_name[0]  }
  end

  def get_list_certs(type)

    if @root_ca.nil?
      @error = I18n.t('errors.root_ca_not_detected')
      return []
    end

    index_txt_path = "#{@root_ca}/ca/intermediate/index.txt"
    unless File.exist?(index_txt_path)
      @error = I18n.t('errors.root_ca_not_detected')
      return []
    end

    ca_index_txt = File.read(index_txt_path, encoding: 'utf-8').split("\n").each_with_object([]) do |line, entries|
      match = line.split("\t")
      next if match.length != 6

      exp = false
      date_tm = parse_time_string(match[1])
      if date_tm.nil?
        date_tm = "нет даты"
      else
        exp = date_tm[1] < DateTime.now
        date_tm = date_tm[0]
      end

      date_tm_revoke = parse_time_string(match[2])
      if date_tm_revoke.nil?
        date_tm_revoke = "нет даты"
      else
        date_tm_revoke = date_tm_revoke[0]
      end

      prep = { id: match[3], status: match[0], date: date_tm, fld: match[4], ui: nil, revoke_date: date_tm_revoke, expired: exp }

      parts = match[5].split('/').reject(&:empty?).map(&:strip)
      cert_info = {}
      parts.each do |part|
        key, value = part.split('=', 2)
        key_downcased = key.upcase
        cert_info[key_downcased.to_sym] = value || 'default_value'
      end

      prep[:ui] = cert_info

      cl_name = prep[:ui][:O].split(":")
      cert_file = if cl_name.length > 1
        "#{@root_ca}/ca/client_certs/#{prep[:ui][:CN]}/#{cl_name[0]}.cert.pem.#{cl_name[1]}"
      else
        "#{@root_ca}/ca/client_certs/#{prep[:ui][:CN]}/#{cl_name[0]}.cert.pem"
      end

      if type == '*'
        entries << prep
      else
        if File.exist?(cert_file)
          entries << prep if type == 'c'
        elsif type == 's'
          entries << prep
        end
      end
    end

    ca_index_txt.sort_by! { |entry| entry[:id] }

    ca_index_txt
  end

  def parse_time_string(str)
    return nil if str.nil? || str.length != 13 || !str[10..11].match?(/[0-9]{2}/)
    year = str[0..1].to_i + 2000 # Первые два символа - год
    month = str[2..3].to_i # Следующие два символа - месяц
    day = str[4..5].to_i # Еще два символа - день
    hour = str[6..7].to_i # Следующие два символа - часы
    minute = str[8..9].to_i # Еще два символа - минуты
    second = str[10..11].to_i # Последние два символа - секунды
    utc_offset = 0 # По умолчанию считаем, что строка содержит Z, т.е. UTC
    [ DateTime.new(year, month, day, hour, minute, second, utc_offset).strftime('%d-%m-%y %H:%M:%S'),
      DateTime.new(year, month, day, hour, minute, second, utc_offset) ]
  end

  def get_cert_id_by_name(server_name, seq, org_name, type)
    org_nm = nil
    config_sh = File.read('utils/custom_config.sh')
    match = config_sh.match(/ORG_NAME="([^"]+)"/)
    org_nm = match[1] if match
    return nil if org_nm.nil?
    list_certs = get_list_certs('*')

    if type == 's'

      found_entry = list_certs.find do |entry|
        if seq == ''
          "#{org_nm}" == entry[:ui][:O] && server_name == entry[:ui][:CN]
        else
          "#{org_nm}:#{seq}" == entry[:ui][:O] && server_name == entry[:ui][:CN]
        end
      end
    else
      found_entry = list_certs.find do |entry|
        if seq == ''
          "#{org_name}" == entry[:ui][:O] && server_name == entry[:ui][:CN]
        else
          "#{org_name}:#{seq}" == entry[:ui][:O] && server_name == entry[:ui][:CN]
        end
      end
    end

    if found_entry
      found_entry
    else
      nil
    end
  end
end
