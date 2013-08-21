# Conserve - linux backup tool.
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

class Log
  attr_accessor :start_time
  attr_reader :log_file

  def initialize()
    @log_file = nil
    @log_enabled = false
    @start_time = nil # don't remember why i need it, hope to findout later
    @skip_time = false
  end

  def enable # start log to file instead of stdout
    @log_enabled = true
  end

  # Write colored text to output WITH custom end of line.
  #
  def write_with_eol(info = nil, color = nil, interactive = false, eol = "\n")
    colored_info = to_paint(info, color)
    if @log_enabled == true
      to_log(colored_info, eol)
      to_stdout(colored_info, eol) if interactive
    else
      to_stdout(colored_info, eol)
    end
  end

  # Write colored text to output WITH "end of line".
  #
  def write(info = nil, color = nil, interactive = false)
    write_with_eol(info, color, interactive)
  end

  # Writing colored text to output WITHOUT "end of line".
  #
  def write_noel(info=nil, color=nil, interactive=false)
    write_with_eol(info, color, interactive, '')
  end

  private

  # Printing to stdout with or without "end of line" character.
  #
  def to_stdout(info, eol)
    print info + eol
  end

  # Printing to file with or without "end of line" character.
  #
  def to_log(info, eol)
    begin
      File.open(log_file, "a") do |file|
          @start_time = Time.now.asctime
          if @skip_time
            file.print info + eol
            @skip_time = false
          else
            file.print "#{@start_time} - #{info}#{eol}"
          end
      end
      status = 0
      error = nil
    rescue
      status = 1
      error = $!
    end
    [status, error]
  end

  # Painting text if color defined.
  #
  def to_paint(info, color)
    colored_info = case color
      when nil then info
      when 'red' then red(info)
      when 'yellow' then yellow(info)
      when 'green' then green(info)
      when 'sky_blue' then sky_blue(info)
      else info
    end
  end

  # Add color code to start of string and static "end of color" to the end of string.
  #
  def colorize(text, color_code)
    "#{color_code}#{text}\e[0m"
  end

  # Number of color with codes of them.
  #
  def red(text); colorize(text, "\e[31m"); end
  def green(text); colorize(text, "\e[32m"); end
  def yellow(text); colorize(text, "\e[33m"); end
  def sky_blue(text); colorize(text, "\e[36m"); end
end
