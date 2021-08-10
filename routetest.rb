require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'
  gem 'pry'
  gem 'haml', '5.2.2'
  gem 'activesupport', '6.1.4'
end

require 'json'

# File source:
overpass_export = JSON.parse(File.open("export.geojson").read)
coordinates = overpass_export["features"].map{|f| f["geometry"]["coordinates"][0]}

# Bounding box:
bounding_box_1 = [55.70003, 12.44279]
bounding_box_2 = [55.7434, 12.52201]

latitude_bound = ([bounding_box_1[0], bounding_box_2[0]].min .. [bounding_box_1[0], bounding_box_2[0]].max)
longitude_bound = ([bounding_box_1[1], bounding_box_2[1]].min .. [bounding_box_1[1], bounding_box_2[1]].max)

filtered_coordinates = [].tap do |it|
  coordinates.each do |longitude, latitude|
    if longitude_bound.include?(longitude) && latitude_bound.include?(latitude)
      it << [longitude, latitude]
    end
  end
end

MAX_AMOUNT_OF_COORDINATES = 25
raise "Too many coordinates, #{MAX_AMOUNT_OF_COORDINATES} allowed but #{filtered_coordinates.size} found" if filtered_coordinates.size > MAX_AMOUNT_OF_COORDINATES

require 'pry'; binding.pry

# Build the problem
problem = {}
problem['vehicles'] = []
problem['vehicles'] << {
  'id' => 1,
  'start' => [12.544503, 55.704759],
  'end' => [12.544503, 55.704759],
  'profile' => 'cycling-regular',
}
problem['jobs'] = []
filtered_coordinates.each_with_index do |longlat, index|
  longitude, latitude = longlat
  problem['jobs'] << {'id' => index, 'location' => [longitude, latitude]}
end
# puts problem
require 'pry'; binding.pry

# Contact API
# https://openrouteservice.org/dev/#/api-docs/optimization/post
require_relative 'api_key.rb'
openrouteservice_key = API_KEY

require 'net/http'
require 'net/https'
begin
  uri = URI('https://api.openrouteservice.org/optimization')

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.verify_mode = OpenSSL::SSL::VERIFY_PEER

  req =  Net::HTTP::Post.new(uri)
  req.add_field "Authorization", openrouteservice_key
  req.add_field "Content-Type", "application/json"
  req.body = JSON.dump(problem)

  res = http.request(req)
  # puts "Response HTTP Status Code: #{res.code}"
  # puts "Response HTTP Response Body: #{res.body}"
  route_data = JSON.parse(res.body)
rescue StandardError => e
  puts "HTTP Request failed (#{e.message})"
  raise
end

raise 'There are unassigned jobs' if route_data['unassigned'].any?
raise 'There are more than one route' if route_data['routes'].size > 1

# Render html for route description
require 'haml'
require 'ostruct'
require 'active_support/all'

def humanized_duration(seconds)
  ActiveSupport::Duration.build(seconds).parts.except(:seconds).reduce("") do |output, (key, val)|
    output += "#{val}#{key.to_s.first} "
  end.strip
end

route_steps = [].tap do |it|
  route_data['routes'].first['steps'].each do |step|
    it << OpenStruct.new(type: step['type'], longitude: step['location'][0], latitude: step['location'][1], arrival: humanized_duration(step['arrival']), arrival_s: step['arrival'])
  end
end
# puts route_data
require 'pry'; binding.pry

data_binding = OpenStruct.new(route_steps: route_steps)
haml_template = File.open('route.haml').read
engine = Haml::Engine.new(haml_template)
File.write("route.html", engine.render(data_binding))
