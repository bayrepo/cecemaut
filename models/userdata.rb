require 'i18n'
require_relative 'users'

class UserSessionData
  attr_accessor :user_info, :error

  def initialize(name, password, init = nil)
    @user_info = nil
    @error = nil
    if init.nil?
      user = get_user(name, password)
      if user
        @user_info = user
      else
        @error = I18n.t('errors.invalid_username_password')
      end
    end
  end

  def auth?
    !@user_info.nil?
  end

  def role
    if auth?
      @user_info[:role]
    else
      -1
    end
  end

  def user_info
    @user_info
  end

  def add_user(name, password, email, role)
    @error = nil
    user = User.where(login: name).first
    if user
      @error = I18n.t('errors.user_already_exists')
    else
      User.create(login: name, password: Digest::SHA256.hexdigest(password.strip), email: email, role: role)
    end
  end

  def list_users()
    User.order(Sequel.asc(:login)).all
  end

  def user_info(name, id = nil)
    @error = nil
    if name.nil? && id.nil?
      @error = I18n.t('errors.search_parameters_not_set')
      retrun nil
    end
    user = nil
    if id.nil?
      user = User.where(login: name).first
    else
      user = User.where(id: id).first
    end
    if user
      user
    else
      @error = I18n.t('errors.user_not_found')
      nil
    end
  end

  def del_user(name, id = nil)
    @error = nil
    if name.nil? && id.nil?
      @error = I18n.t('errors.search_parameters_not_set')
      return
    end
    user = nil
    if id.nil?
      user = User.where(login: name).first
    else
      user = User.where(id: id).first
    end
    if user
      user.delete
    else
      @error = I18n.t('errors.user_not_found')
    end
  end

  def update_user(name, password, email, role, id = nil)
    @error = nil
    if name.nil? && id.nil?
      @error = I18n.t('errors.search_parameters_not_set')
      return
    end
    user = nil
    if id.nil?
      user = User.where(login: name).first
    else
      user = User.where(id: id).first
    end
    if user
      changes = {}
      changes[:password] = Digest::SHA256.hexdigest(password) unless password.nil? || password.empty?
      changes[:email] = email unless email.nil? || email.empty?
      changes[:role] = case role.to_i
                        when 0 then 0
                        when 1 then 1
                        when 2 then 2
                        else user[:role]
                        end
      user.update(changes) unless changes.empty?
    else
      @error = I18n.t('errors.user_not_found')
    end
  end

  def err
    @error
  end

  def tok
    @user_info.nil?
  end

  def login
    @user_info[:login]
  end

  # Методы для сериализации и десериализации объекта в JWT токене
  def serialize
    { user_info: @user_info.to_hash, error: @error }.to_json
  end

  def self.deserialize(token)
    data = JSON.parse(token, symbolize_names: true)
    instance = new(nil, nil, true)
    user_data = data[:user_info]

    instance.instance_variable_set(:@user_info, user_data)
    instance.instance_variable_set(:@error, data[:error])
    instance
  end

  private

  def get_user(name, password)
    user = User.where(login: name).first
    return unless user && user[:password] == Digest::SHA256.hexdigest(password)

    user
  end
end
