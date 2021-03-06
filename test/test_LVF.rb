#
# test the Las Vegas Filter (LVF) algorithm
#
require 'fselector'

puts "\n>============> #{File.basename(__FILE__)}"

# example 1
#


r = FSelector::LVF.new
r.data_from_random(100, 3, 10, 5, false)

# number of features before feature selection
puts '  # features (before): ' + r.get_features.size.to_s

# feature selection
r.select_feature!

# number of features after feature selection
puts '  # features (after): ' + r.get_features.size.to_s

puts "<============< #{File.basename(__FILE__)}"
