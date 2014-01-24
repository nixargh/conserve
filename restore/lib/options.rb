# ahco - restore utility for Conserve backups.
#
# Copyright (C) 2013  nixargh <nixargh@gmail.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see http://www.gnu.org/licenses/gpl.html.


# This file is for options parsing.
#
def parse_options
  puts "\tParsing options from array: #{ARGV}..." if $debug
  require 'optparse'

  # Explanation for options.
  #
  help = Hash.new()
  help[:help] = "show this message"
  help[:debug] = "be verbose - show debug information"
  help[:source] = "source file"
  help[:dest] = "destination file"
  help[:mbr] = "restore Master Boot Record"

  # Parse options
  # 
  options = Hash.new(false)

  OptionParser.new do |params|
    params.banner = "Usage: #{$0} [options]"

    params.on('-h', '--help', help[:help]) do
      options[:help] = true
      puts params
      exit 0
    end

    params.on('-V', '--debug', help[:debug]) do
      options[:debug] = true
    end

    params.on('-s', '--source SOURCE', help[:source]) do |source|
      options[:source] = source
    end

    params.on('-d', '--dest DESTINATION', help[:dest]) do |destination|
      options[:dest] = destination
    end

    params.on('-m', '--mbr', help[:mbr]) do |mbr|
      options[:mbr] = mbr
    end
  end.parse!

  options
end
