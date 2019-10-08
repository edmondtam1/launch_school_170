require 'tilt/erubis'
require 'sinatra'
require 'sinatra/reloader' if development?
require 'yaml'

before do
  @users = YAML.load_file('users.yaml')
end

helpers do
  def count_interests
    num = 0
    @users.each do |_, v|
      num += v[:interests].size
    end
    num
  end
end

get "/" do
  erb :home
end

get "/users/:username" do
  @user = params[:username]
  @user_data = @users[@user.to_sym]
  erb :user
end

not_found do
  redirect "/"
end
