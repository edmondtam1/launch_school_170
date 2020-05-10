ENV["RACK_ENV"] = "test"

require "minitest/autorun"
require "rack/test"
require "fileutils"
require "bcrypt"

require_relative "../cms"

class CMSTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    FileUtils.mkdir_p(data_path)
  end

  def teardown
    FileUtils.rm_rf(data_path)
  end

  def create_test_doc(name, content = "")
    File.open(File.join(data_path, name), "w") do |f|
      f.write(content)
    end
  end

  def session
    last_request.env["rack.session"]
  end

  def admin_session
    { "rack.session" => { username: "admin" } }
  end
  
  # Beginning of test suite

  def test_index
    create_test_doc "about.md"
    create_test_doc "changes.txt"

    get "/"
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "about.md"
    assert_includes last_response.body, "changes.txt"
    assert_includes last_response.body, "New Document"
  end

  def test_view_txt_file
    create_test_doc "history.txt", %q(History (from Greek ἱστορία, historia, meaning 'inquiry; knowledge acquired by investigation')[2] is the past as it is described in written documents, and the study thereof.[3][4] Events occurring before written records are considered prehistory. "History" is an umbrella term that relates to past events as well as the memory, discovery, collection, organization, presentation, and interpretation of information about these events. Scholars who write about history are called historians.)

    get "/history.txt"
    assert_equal 200, last_response.status
    assert_equal "text/plain", last_response["Content-Type"]
    assert_match "History (from Greek ἱστορία, historia,", last_response.body
    assert_includes last_response.body, "History (from Greek ἱστορία, historia,"
  end

  def test_document_not_found
    get "/bogus.link" # Attempt to connect to a fake path
    assert_equal 302, last_response.status # Check if response redirects
    assert_equal "bogus.link does not exist.", session[:message]
  end

  def test_render_markdown
    create_test_doc "about.md", "# An h1 header"

    get "/about.md" # Load the .md file
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "<h1>An h1 header</h1>"
  end

  def test_edit_document
    create_test_doc "changes.txt"

    get "/changes.txt/edit", {}, admin_session # Load the relevant file
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "<textarea"
    assert_includes last_response.body, %q(<input type="submit")
  end

  def test_edit_document_signed_out
    create_test_doc "changes.txt"

    get "/changes.txt/edit"
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_update_document
    post "/changes.txt/edit", { edited_text: "New content" }, admin_session
    assert_equal 302, last_response.status
    assert_equal "changes.txt has been updated.", session[:message]

    get "/changes.txt"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "New content"
  end

  def test_update_document_signed_out
    post "/changes.txt/edit", { edited_text: "New content" }
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_view_new_document_form
    get "/new", {}, admin_session
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Add a new document:"
    assert_includes last_response.body, %q(<input type="text" name="name">)
    assert_includes last_response.body, %q(<button type="submit")
  end

  def test_view_new_document_form_signed_out
    get "/new", {}
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_create_new_document
    post "/new", { name: "test_doc.txt" }, admin_session
    assert_equal 302, last_response.status
    assert_equal "test_doc.txt was created.", session[:message]

    get "/"
    assert_includes last_response.body, "test_doc.txt"
  end

  def test_create_new_document_signed_out
    post "/new", { name: "test_doc.txt" }
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_create_empty_document
    post "/new", { name: "" }, admin_session
    assert_equal 422, last_response.status
    assert_includes last_response.body, "A name is required."
  end

  def test_delete_document
    create_test_doc("test.txt")

    post "/test.txt/delete", {}, admin_session
    assert_equal 302, last_response.status
    assert_equal "test.txt was deleted.", session[:message]

    get "/"
    refute_includes last_response.body, %q(href="/test.txt")
  end

  def test_delete_document_signed_out
    create_test_doc("test.txt")

    post "/test.txt/delete", {}
    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_signin_form
    get "/users/signin"

    assert_equal 200, last_response.status
    assert_includes last_response.body, "<input"
    assert_includes last_response.body, %q(<button type="submit">Sign In)
  end

  def test_signin_as_admin
    write_user_credentials({ 'admin' => BCrypt::Password.create('secret').to_s })
    post "/users/signin", { username: 'admin', password: 'secret' }

    assert_equal 302, last_response.status
    assert_equal "Welcome!", session[:message]
    assert_equal "admin", session[:username]

    get last_response["Location"]
    assert_includes last_response.body, "Signed in as admin"
    assert_includes last_response.body, %q(<button type="submit">Sign out)
    refute_includes last_response.body, %q(Sign in)
  end

  def test_signin_as_other_user
    post "/users/signin", username: "not", password: "valid"

    assert_equal 422, last_response.status
    assert_nil session[:username]
    assert_includes last_response.body, "Invalid Credentials"
  end

  def test_signout
    get "/", {}, admin_session
    assert_includes last_response.body, "Signed in as admin"

    post "/users/signout"
    assert_equal "You have been signed out.", session[:message]

    get last_response["Location"]
    assert_nil session[:username]
    assert_includes last_response.body, "Sign In"
  end

  def test_user_signed_in_check
    get "/new"
    assert_equal session[:message], "You must be signed in to do that."
  end

  def test_duplicate_documents
    create_test_doc("test.txt")

    post "/test.txt/duplicate", {}, admin_session
    assert_equal 302, last_response.status

    get last_response["Location"]
    assert_includes last_response.body, "test_cp.txt"
  end

  def test_valid_credentials_signup
    write_user_credentials({ 'test' => 'password'})
    post "/users/signup", { username: 'valid', password: 'Credentials1!' }

    assert_equal 302, last_response.status
    assert_equal "Your account has been created.", session[:message]

    credentials = load_user_credentials
    assert_includes credentials, "valid"
    assert BCrypt::Password.new(credentials['valid']) == "Credentials1!"
  end

  def test_duplicate_username_signup
    write_user_credentials({ 'invalid' => 'invalid_test' })
    post "/users/signup", { username: 'invalid', password: 'Password1!' }

    assert_equal 422, last_response.status
    assert_equal "This username has already been taken.", session[:message]
  end

  def test_invalid_username_signup
    post "/users/signup", { username: 'invalid!', password: 'Password1!'}

    assert_equal 422, last_response.status
    assert_equal "Please enter a valid username (letters and digits only).", session[:message]
  end

  def test_invalid_password_signup

  end
end
