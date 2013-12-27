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

def parse_options
  require 'optparse'

# Explanation for options.
#
  help = Hash.new('don\'t know')
  help[:help] = <<-eos
"AHCO  Copyright (C) 2013  nixargh <nixargh@gmail.com>
This program comes with ABSOLUTELY NO WARRANTY.
This is free software, and you are welcome to redistribute it
under certain conditions.\n
AHCO v.#{$version}
- is a restore utility for Conserve backups, which can do:
\t0. Nothing :)\n
eos

  # Parse options
  # 
  options = Hash.new(false)

  OptionParser.new do |params|
    params.banner = "Usage: #{$0} [options]"

    params.on('-h', '--help', help[:help]) do
      options[:help] = true
    end
  end
