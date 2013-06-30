# -*- coding: utf-8 -*-
require "simple_oauth"
require "net/http/post/multipart"
require "rexml/document"
require "json"

def select_image
  dialog = Gtk::FileChooserDialog.new("Select Upload Image",
                                      nil,
                                      Gtk::FileChooser::ACTION_OPEN,
                                      nil,
                                      [Gtk::Stock::CANCEL, Gtk::Dialog::RESPONSE_CANCEL],
                                      [Gtk::Stock::OPEN, Gtk::Dialog::RESPONSE_ACCEPT])

  filter = Gtk::FileFilter.new
  filter.name = "Image Files"
  ["png", "jpg", "jpeg", "gif"].each do |n|
    filter.add_pattern("*.#{n}")
    filter.add_pattern("*.#{n.upcase}")
  end
  dialog.add_filter(filter)

  dialog.preview_widget = Gtk::Image.new
  dialog.signal_connect("update-preview") do
    if dialog.preview_filename && !File.directory?(dialog.preview_filename)
      dialog.preview_widget.set_pixbuf(Gdk::Pixbuf.new(dialog.preview_filename, 128, 128))
      dialog.set_preview_widget_active(true)
    else
      dialog.set_preview_widget_active(false)
    end
  end

  if dialog.run == Gtk::Dialog::RESPONSE_ACCEPT
    filename = dialog.filename.to_s
  else
    filename = nil
  end
  dialog.destroy

  return filename
end

def upload(url, filename, options)
  uri = URI.parse(url)
  provider = "https://api.twitter.com/1.1/account/verify_credentials.json"
  keys = {consumer_key: CHIConfig::TWITTER_CONSUMER_KEY,
          consumer_secret: CHIConfig::TWITTER_CONSUMER_SECRET,
          token: UserConfig[:twitter_token],
          token_secret: UserConfig[:twitter_secret]}

  Net::HTTP.start(uri.host, uri.port) do |http|
    params = options.merge({media: UploadIO.new(filename,
                                                "application/octet-stream",
                                                File.basename(filename))})

    req = Net::HTTP::Post::Multipart.new(uri.path, params)

    h = SimpleOAuth::Header.new("GET", provider, {}, keys)
    req["X-Auth-Service-Provider"] = provider
    req["X-Verify-Credentials-Authorization"] = "OAuth realm=\"http://api.twitter.com/\", " +
                                                h.__send__(:normalized_attributes)
    return http.request(req).body
  end
end

def create_command(name, slug, url, options = {}, &parse)
  command("upload_to_#{slug}".to_sym,
          name: "画像を#{name}にアップロードする",
          condition: -> _ { true },
          visible: true,
          role: :postbox) do |opt|
    begin
      filename = select_image

      if filename
        body = upload(url, filename, options)
        url = parse.call(body)
        Plugin.create(:gtk).widgetof(opt.widget).widget_post.buffer.text += " " + url
      end
    rescue Exception => e
      Plugin.call(:update, nil, [Message.new(message: e.to_s, system: true)])
    end
  end
end


Plugin.create :image_upload do
  create_command("ついっぷるフォト", "twipple_photo", "http://p.twipple.jp/api/upload2") do |body|
    REXML::XPath.first(REXML::Document.new(body), "//rsp/mediaurl").text
  end
  create_command("yfrog", "yfrog", "http://yfrog.com/api/xauth_upload", key: "278EMSVYb5f62c5e59793ab2df33315ab6041498") do |body|
    JSON.parse(body)["rsp"]["mediaurl"]
  end
  create_command("img.ly", "imgly", "http://img.ly/api/2/upload.xml") do |body|
    REXML::XPath.first(REXML::Document.new(body), "//image/url").text
  end
  create_command("twitpic", "twitpic", "http://api.twitpic.com/2/upload.xml", key: "b1277fb422e6145ee44cbb465a48e7be", message: "") do |body|
    REXML::XPath.first(REXML::Document.new(body), "//image/url").text
  end
end

