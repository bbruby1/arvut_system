require 'feed_tools'
require 'yaml'

module FeedReader
  class Basic
    attr :feed
    
    def initialize(url, lang_id = nil, force = false)
      lang_id ||= Language.get_id_by_locale(I18n.locale)
      unless force
        cache = Cache.where(:content_type => 'FeedReader', :content_uid => "#{url}", :language_id => lang_id).first
        @feed = YAML.load(cache.content) if cache
      end
      @feed ||= FeedTools::Feed.open(url)
    end

    def self.store_in_cache
      Language.all.each{|lang|
        locale = lang.locale.to_sym
        lang_id = Language.get_id_by_locale(locale)
        url = I18n.t('home.views.feed', :locale => locale)
        @feed = FeedReader::Basic.new(url, lang_id, true).feed
        cache = Cache.new(:content_type => 'FeedReader', :content_uid => "#{url}", :language_id => lang_id,
          :content => YAML.dump(@feed)
        )
        cache.save!
        puts "FeedReader: #{locale} - #{url} - stored"
      }
    end
  end
end