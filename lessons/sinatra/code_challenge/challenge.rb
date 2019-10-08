require 'tilt/erubis'
require "sinatra"
require "sinatra/reloader"

get "/" do
  @files = Dir.glob("public/*").map { |fn| File.basename(fn, '.*') }.sort
  @files.reverse! if params[:sort] == "desc"
  puts params
  erb :home
end
