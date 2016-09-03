require 'rubygems'
require 'bundler/setup'

require 'twitter'
require 'dotenv'
require 'flickraw'
require 'bloomfilter-rb'
require 'fileutils'
require 'open-uri'
#require 'tracery'
#include Tracery

Dotenv.load

FILTER_FILE = File.join(__dir__, "..", "etc", "filter")
IMAGE_FILE = File.join(__dir__, "..", "etc", "photo")

#TODO Ensure BloomFilter is properly configured
if File.exists?(FILTER_FILE)
  filter = BloomFilter::Native.load( FILTER_FILE  )
else
  filter = BloomFilter::Native.new(:size => 100, :hashes => 2, :seed => 1, :bucket => 3, :raise => false)
end

discovery = 
  ["date-posted-asc", "date-posted-desc", "date-taken-asc", "date-taken-desc", "interestingness-desc", "interestingness-asc", "relevance"].sample

puts "Discovery method: #{discovery}"

# Search and find an image, right location and licence
# Check whether in bloom filter
def choose_image(discovery, filter)
  
  FlickRaw.api_key=ENV["FLICKR_KEY"]
  FlickRaw.shared_secret=ENV["FLICKR_SECRET"]

  bath = flickr.places.find :query => "Bath"
  latitude = bath[0]['latitude'].to_f
  longitude = bath[0]['longitude'].to_f

  args = {}
  args[:place_id] = bath[0]['place_id']
  args[:accuracy] = 11 #city
  args[:per_page] = 500 #this is max size
  #license ids at: https://www.flickr.com/services/api/flickr.photos.licenses.getInfo.html
  args[:license] = "7,6,5,4,3,2,1"
  args[:sort] = discovery
    
  images = flickr.photos.search args
  #puts images.inspect
  images.to_a.shuffle.each do |i|
    if !filter.include?( i["id"] )
      filter.insert( i["id"] )
      return i
    end
  end 
  raise "No image!"
end  

def send_tweet(discovery, image)
  
  # Download small image
  open(IMAGE_FILE, 'wb') do |file|
    file << open( FlickRaw.url(image)).read
  end
  
  client = Twitter::REST::Client.new do |config|
    config.consumer_key        = ENV["TWITTER_CK"]
    config.consumer_secret     = ENV["TWITTER_CS"]
    config.access_token        = ENV["TWITTER_AT"]
    config.access_token_secret = ENV["TWITTER_AS"]
  end

  photo = flickr.photos.getInfo( { "photo_id" => image["id"] } )
  puts photo.inspect
  
  case discovery
  when "date-posted-asc"
    phrase = "Discovered pixels!"
  when "date-posted-desc"
    phrase = "Shared pixels!"
  when "date-taken-asc"
    phrase = "Old pixels,"
  when "date-taken-desc"
    phrase = "New pixels!"
  when "interestingness-desc"
    phrase = "Interesting pixels!"
  when "interestingness-asc"
    phrase = "Hmm, pixels?"
  when "relevance"
    phrase = "Useful pixels!"   
  end
  
  user = photo["owner"]["realname"].empty? ? photo["owner"]["username"] : photo["owner"]["realname"]
  title = photo["title"].empty? ? "Photo" : photo["title"]
        
  msg = "#{phrase} #{ title } by #{ user } #{FlickRaw.url_photopage(image)}"
    
  # TODO improve
  # Google Image description?
  
  # Post tweet with image  
  puts photo["location"]["latitude"]
  client.update_with_media(msg, File.new( IMAGE_FILE ), lat: photo["location"]["latitude"].to_f, long: photo["location"]["longitude"].to_f, display_coordinates: true )

  puts msg
    
end 

image = choose_image(discovery, filter)
send_tweet( discovery, image )
filter.save( FILTER_FILE )

