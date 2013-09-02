#!/usr/bin/ruby
#### INFO ######################################################################
# script to test Conserve
# (*w) author: nixargh <nixargh@gmail.com>
$version = '0.1'
################################################################################

class Test
  def initialize
    @binary = './conserve'
    log = '-l /var/log/conserve_test.log'
    report = '-i /etc/conserve/test.inform.conf'
    @tail = "#{log} #{report}"
    @tests_config = ARGV[0]
  end

  # Runs tests
  #
  def run
    vars = read_vars
    tests = substitute_vars(vars, read_tests_list)
    tests_num = 0
    failed_tests = tests.each.inject([]) do |failed_tests, test|
      tests_num += 1
      test_name, test_argv = test.split(']')
      print "#{test_name.delete('[')} - "
      if run_cmd(test_argv)
        puts "[ #{green('PASSED')} ]"
        next(failed_tests)
      else
        puts "[ #{red('FAILED')} ]"
        failed_tests << test
      end
    end
    puts "\nTests Failed: #{failed_tests.length} from #{tests_num}."
  end

  private

  # Gets variables from config
  #
  def read_vars
    vars = Hash.new
    read_config_file.each do |line|
      next if line.index('@') != 0
      var, value = line.split('=')
      vars[var.strip] = value.strip
    end
    vars
  end    

  # Get tests list from config
  #
  def read_tests_list
    read_config_file.each.inject([]) do |tests, line|
      line.index('[') == 0 ? tests << line.chomp : tests
    end
  end

  # Substitute variables by they values
  #
  def substitute_vars(vars, tests)
    tests.each.inject([]) do |tests, test|
      test.gsub!(/[@]\S+/, vars)
      tests << test
    end
  end

  # Reads tests config file
  #
  def read_config_file
    raise "Test config file not specified!" if !@tests_config
    IO.read(@tests_config).each_line.inject([]) do |useful_lines, line|
      line.index('#') != 0 ? useful_lines << line.chomp : useful_lines
    end
  end

  # Compile conserve command line
  #
  def run_cmd(test)
    cmd = "#{@binary} #{test} #{@tail}"
    system("#{cmd} 2>/dev/null 1>/dev/null")
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
end

################################################################################
test = Test.new
test.run
