#!/usr/bin/ruby
#### INFO ######################################################################
# script to test Conserve
# (*w) author: nixargh <nixargh@gmail.com>
$version = '0.1'
################################################################################

class Test
  require 'benchmark'

  def initialize(file)
    @binary = './conserve'
    log = '-l /var/log/conserve_test.log'
    report = '-i /etc/conserve/test.inform.conf'
    @tail = "#{log} #{report}"
    @tests_config = file
    @last_failed_file = "#{File.dirname(@tests_config)}/last_failed_tests"
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
      test_name.delete!('[')
      print "#{test_name} - "
      test_name.strip!
      test_argv.gsub!('@name', test_name.gsub(' ', '_'))
      test_argv = test_argv + " -n \"#{test_name}\""
      status = false
      run_time = Benchmark.measure { status = run_cmd(test_argv) }
      if status
        puts "[ #{green('PASSED')} ]\t\t#{run_time}"
        next(failed_tests)
      else
        puts "[ #{red('FAILED')} ]\t\t#{run_time}"
        failed_tests << test
      end
    end
    puts "\nTests Failed: #{failed_tests.length} from #{tests_num}."
    save_failed(failed_tests)
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

  # Save failed tests list to file
  #
  def save_failed(failed_tests)
    File.open(@last_failed_file, 'w+') do |file|
      failed_tests.each { |test| file.puts(test) }
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
begin
  if (file = ARGV[0])
    test = Test.new(file)
    test.run
    exit 0
  else
    puts "You should specify config file."
    exit 1
  end
rescue
  puts $!
  puts $!.backtrace
  exit 1
end
