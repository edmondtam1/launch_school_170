require "sinatra"
require "sinatra/reloader" if development?
require "tilt/erubis"
require "redcarpet"
require "yaml"
require "bcrypt"
require "fileutils"

configure do
  enable :sessions
  set :session_secret, 'secret'
  # set :erb, escape_html: true
end

# Helper functions

def render_markdown(text)
  markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
  markdown.render(text)
end

def load_file_content(path)
  content = File.read(path)

  case File.extname(path)
  when ".txt"
    headers["Content-Type"] = "text/plain"
    content
  when ".md"
    erb render_markdown(content)
  end
end

def data_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/data", __FILE__)
  else
    File.expand_path("../data", __FILE__)
  end
end

def write_user_credentials(data)
  user_path = if ENV["RACK_ENV"] == "test"
                File.expand_path("../test/users.yml", __FILE__)
              else
                File.expand_path("../users.yml", __FILE__)
              end
  File.write(user_path, YAML.dump(data))
end

def load_user_credentials
  user_path = if ENV["RACK_ENV"] == "test"
                File.expand_path("../test/users.yml", __FILE__)
              else
                File.expand_path("../users.yml", __FILE__)
              end
  YAML.load_file(user_path)
end

def validate_filename(name)
  name = name.split(".").map(&:strip)
  if name.empty?
    "A name is required."
  elsif name[1].nil? || name[2]
    "Please enter a valid name."
  elsif !['txt', 'md'].include? name[1]
    "Please enter a valid file extension (.txt or .md)."
  end
end

def valid_login?(username, password)
  credentials = load_user_credentials

  if credentials.key?(username)
    bcrypt_password = BCrypt::Password.new(credentials[username])
    bcrypt_password == password
  else
    false
  end
end

def signed_in?
  !!session[:username]
end

def require_signed_in_user
  unless signed_in?
    session[:message] = "You must be signed in to do that."
    redirect "/"
  end
end

def validate_username(username)
  credentials = load_user_credentials
  if credentials.key?(username)
    "This username has already been taken."
  elsif !!username.match(/[^a-zA-Z0-9]/)
    "Please enter a valid username (letters and digits only)."
  end
end

def validate_password(password)
  unless !!password.match(/\A(?=.*?[A-Z])(?=.*?[a-z])(?=.*?[0-9])(?=.*?[#?!@$%^&*-]).{8,}\z/)
    "Please key in a valid password."
  end
end

# End of helper functions

# Load the index page
get "/" do
  pattern = File.join(data_path, "*")
  @filenames = Dir.glob(pattern).map { |d| File.basename(d) }.sort
  erb :index
end

# Create a new document
get "/new" do
  require_signed_in_user
  erb :new
end

# Submit the new document name
post "/new" do
  require_signed_in_user
  error = validate_filename(params[:name])
  if error
    session[:message] = error
    status 422
    erb :new
  else
    File.new(File.join(data_path, params[:name]), "w+")
    session[:message] = "#{params[:name]} was created."
    redirect "/"
  end
end

# Get a page for a file in the data folder
get "/:filename" do
  file_path = File.join(data_path, File.basename(params[:filename]))

  if File.exist?(file_path)
    load_file_content(file_path)
  else
    session[:message] = "#{File.basename(file_path)} does not exist."
    redirect "/"
  end
end

# Edit a file's contents
get "/:filename/edit" do
  require_signed_in_user
  file_path = File.join(data_path, params[:filename])
  if File.exist?(file_path)
    @file_content = File.read(file_path)
    erb :edit
  else
    session[:message] = "#{File.basename(file_path)} does not exist."
    redirect "/"
  end
end

# Post the changes to the file's contents
post "/:filename/edit" do
  require_signed_in_user
  file_path = File.join(data_path, params[:filename])
  File.write(file_path, params[:edited_text])
  session[:message] = "#{params[:filename]} has been updated."
  redirect "/"
end

# Delete one file
post "/:filename/delete" do
  require_signed_in_user
  file_path = File.join(data_path, params[:filename])
  File.delete(file_path) if File.exist? file_path
  session[:message] = "#{params[:filename]} was deleted."
  redirect "/"
end

# Render signin page
get "/users/signin" do
  erb :signin
end

# Handle signin details
post "/users/signin" do
  username = params[:username]

  if valid_login?(username, params[:password])
    session[:username] = username
    session[:message] = "Welcome!"
    redirect "/"
  else
    session[:message] = "Invalid Credentials"
    status 422
    erb :signin
  end
end

# Handle signout
post "/users/signout" do
  session.delete(:username)
  session[:message] = "You have been signed out."
  redirect "/"
end

# Duplicate the document
post "/:filename/duplicate" do
  require_signed_in_user

  filename, extension = params[:filename].split('.')
  old_file_path = File.join(data_path, params[:filename])
  new_file_path = File.join(data_path, filename + "_cp." + extension)
  FileUtils.cp(old_file_path, new_file_path)
  redirect "/"
end

# User signup form
get "/users/signup" do
  erb :signup
end

# Post user signup data
post "/users/signup" do
  username = params[:username]
  error = validate_username(username) || validate_password(params[:password])
  if error
    session[:message] = error
    status 422
    erb :signup
  else
    credentials = load_user_credentials
    credentials[username] = BCrypt::Password.create(params[:password]).to_s
    write_user_credentials(credentials)
    session[:username] = username
    session[:message] = "Your account has been created."
    redirect "/"
  end
end
