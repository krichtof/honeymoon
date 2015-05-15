require 'json'
require 'nokogiri'
require 'net/http'
require 'wikipedia'

def unquoted_string(text)
  if text =~ Liquid::QuotedString
    return text.strip[1..-2]
  elsif ['true', 'false'].index(text)
    return text == 'true'
  elsif text =~ /^[-+]?[0-9]+$/
    text.to_i
  else
    text
  end
end

module Jekyll
  class WikipediaTag < Liquid::Tag
    Syntax = /^\s*([\w\'\"\s]*?[\w\'\"])(?:\s(\s*#{Liquid::TagAttributes}\s*)(,\s*#{Liquid::TagAttributes}\s*)*)?\s*$/o
    VARIABLE_SYNTAX = /(?<variable>[^{]*\{\{\s*(?<name>[\w\-\.]+)\s*(\|.*)?\}\}[^\s}]*)/
    
    Wikipedia.Configure {
      domain 'fr.wikipedia.org'
      path 'w/api.php'
    }

    def initialize(tag_name, markup, token)
      super
      @attributes = { :lang => "fr"}
      puts "markup: #{markup}"
      matched = markup.strip.match(VARIABLE_SYNTAX)
      if matched
        @text = matched['variable'].strip 
      elsif markup =~ Syntax
        puts "markup #{markup} / #{$1}"
        
        @text = unquoted_string $1.strip

        markup.scan(Liquid::TagAttributes) do |key, value|
          @attributes[key.to_sym] = unquoted_string(value)
        end
        puts "attributes: #{@attributes}"
      end

      @cache_disabled = false
      @cache_folder   = File.expand_path "../.wikipedia-cache", File.dirname(__FILE__)
      FileUtils.mkdir_p @cache_folder
    end

    def render_variable(context)
      if @text.match(VARIABLE_SYNTAX)
        partial = Liquid::Template.parse(@text)
        partial.render!(context)
      end
    end
    
    def render(context)
      @baseurl = context.registers[:site].baseurl
      text = render_variable(context) || @text
      html_output_for(get_cached_article(text) || get_article_from_wikiweb(text))
    end

    def wiki_url()
      "http://%{lang}.wikipedia.org" % @attributes
    end

    def html_output_for(data)
      tpl_data = ""
      File.open(File.expand_path "wikipedia.html", File.dirname(__FILE__)) do |io|
        tpl_data = io.read
      end
      data[:config] = @attributes
      Liquid::Template.parse(tpl_data).render(data)
    end

    def extract_metadata(doc, name)
      def_html = cleanup doc
      puts "after cleanup doc : def_html vaut #{def_html}"
      image_parent = ['.infobox_v2', '.infobox', '.thumb'].find do |container|
        !doc.css(container + ' img').empty?
      end

      full_name = def_html.css('strong')[0].text if def_html.css('strong')[0]
      image = image_parent ? doc.css(image_parent + ' img')[0]['src'] : "#{@baseurl}/images/upload/author-avatar.jpg"
      {
        "code" => def_html.to_html,
        "img_url" => image,
        "wikipedia_url" => wiki_url + "/wiki/" + name,
        "article_name" => full_name
      }
    end


    def get_article_from_wikiweb(name)
      puts "before wiki find"
      page = Wikipedia.find(name, prop: "extracts|images", exintro: true)
      #page = Wikipedia.find(name)
      puts "after wiki find"
      pages = JSON.parse(page.json)['query']['pages']
      html = pages.first[1]["extract"]
      puts "before parse noko"
      doc = Nokogiri::HTML::DocumentFragment.parse html
      puts "before extract metadata"
      data = extract_metadata doc, name
      puts "before cache data: #{data}"
      cache name, data unless @cache_disabled
      data
    end
    
    def get_article_from_web(name)
      puts "get_article_from_web with #{name}"
      raw_uri = URI.parse "#{wiki_url}/w/api.php?action=query&titles=#{CGI.escape(name)}&rvprop=content&prop=revisions&format=json&rvparse=&redirects"
      http    = Net::HTTP.new raw_uri.host, raw_uri.port
      request = Net::HTTP::Get.new raw_uri.request_uri

      data    = http.request request
      data    = data.body
      html = ""
      pages = JSON.parse(data)['query']['pages']

      pages.each { |_, page| html = page['revisions'][0]['*'] }
      puts "pages: #{pages}"

      doc = Nokogiri::HTML::DocumentFragment.parse html
      data = extract_metadata doc, name
      puts "data: #{data}"
      cache name, data unless @cache_disabled
      data
    end

    def cleanup(doc)
      description = doc.xpath("./p")[0]
      puts "after xpath p"
      ['.unicode', '.reference', '.noprint', 'img[alt=play]'].each do |cls|
        description.css(cls).each { |node| node.replace(' ') }
      end

      description.css('b').each do |node|
        puts "node.content #{node.content}"
        
        node.replace("<strong>%s</strong>" % node.content)
      end

      description.css('.IPA').each do |node|
        node.content = node.text if node.text
      end

      description.css('a').each do |node|
        node['href'] = wiki_url + node['href'] if /^\/wiki\//.match(node['href'])
      end

      description
    end

    def get_cached_article(article)
      return nil if @cache_disabled

      cache_file = get_cache_file_for article, @attributes[:lang]
      JSON.parse(File.read cache_file) if File.exist? cache_file
    end

    def cache(article, data)
      cache_file = get_cache_file_for article, @attributes[:lang]

      File.open(cache_file, "w") do |io|
        io.write JSON.generate data
      end
    end

    def get_cache_file_for(article, lang)
      bad_chars = /[^a-zA-Z0-9\-_.]/
      article   = article.gsub bad_chars, ''
      md5       = Digest::MD5.hexdigest "#{article}"

      File.join @cache_folder, "#{article}.#{lang}.cache"
    end
  end
end

Liquid::Template.register_tag('wikipedia', Jekyll::WikipediaTag)
