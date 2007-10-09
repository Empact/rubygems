#!/usr/bin/env ruby
#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'test/unit'
require 'test/gemutilities'
require 'rubygems/config_file'

class TestGemConfigFile < RubyGemTestCase

  def setup
    super

    @temp_conf = File.join @tempdir, '.gemrc'

    @cfg_args = %W[--config-file #{@temp_conf}]
    util_config_file
  end

  def test_initialize
    assert_equal @temp_conf, @cfg.config_file_name

    assert_equal false, @cfg.backtrace
    assert_equal true, @cfg.update_sources
    assert_equal false, @cfg.benchmark
    assert_equal Gem::ConfigFile::DEFAULT_BULK_THRESHOLD, @cfg.bulk_threshold
    assert_equal true, @cfg.verbose
    assert_equal %w[http://gems.example.com], Gem.sources

    File.open @temp_conf, 'w' do |fp|
      fp.puts ":backtrace: true"
      fp.puts ":update_sources: false"
      fp.puts ":benchmark: true"
      fp.puts ":bulk_threshold: 10"
      fp.puts ":verbose: false"
      fp.puts ":sources:"
      fp.puts "  - http://more-gems.example.com"
      fp.puts "install: --wrappers"
    end

    util_config_file

    assert_equal true, @cfg.backtrace
    assert_equal true, @cfg.benchmark
    assert_equal 10, @cfg.bulk_threshold
    assert_equal false, @cfg.verbose
    assert_equal false, @cfg.update_sources
    assert_equal %w[http://more-gems.example.com], Gem.sources
    assert_equal '--wrappers', @cfg[:install]
  end

  def test_initialize_handle_arguments_config_file
    util_config_file %W[--config-file #{@temp_conf}]

    assert_equal @temp_conf, @cfg.config_file_name
  end

  def test_initialize_handle_arguments_config_file_equals
    util_config_file %W[--config-file=#{@temp_conf}]

    assert_equal @temp_conf, @cfg.config_file_name
  end

  def test_handle_arguments
    args = %w[--backtrace --bunch --of --args here]

    @cfg.handle_arguments args

    assert_equal %w[--bunch --of --args here], @cfg.args
  end

  def test_handle_arguments_backtrace
    assert_equal false, @cfg.backtrace

    args = %w[--backtrace]

    @cfg.handle_arguments args

    assert_equal true, @cfg.backtrace
  end

  def test_handle_arguments_benchmark
    assert_equal false, @cfg.benchmark

    args = %w[--benchmark]

    @cfg.handle_arguments args

    assert_equal true, @cfg.benchmark
  end

  def test_handle_arguments_debug
    old_dollar_DEBUG = $DEBUG
    assert_equal false, $DEBUG

    args = %w[--debug]

    @cfg.handle_arguments args

    assert_equal true, $DEBUG
  ensure
    $DEBUG = old_dollar_DEBUG
  end

  def test_handle_arguments_override
    File.open @temp_conf, 'w' do |fp|
      fp.puts ":benchmark: false"
    end

    util_config_file %W[--benchmark --config-file=#{@temp_conf}]

    assert_equal true, @cfg.benchmark
  end

  def test_handle_arguments_traceback
    assert_equal false, @cfg.backtrace

    args = %w[--traceback]

    @cfg.handle_arguments args

    assert_equal true, @cfg.backtrace
  end

  def test_really_verbose
    assert_equal false, @cfg.really_verbose

    @cfg.verbose = true

    assert_equal false, @cfg.really_verbose

    @cfg.verbose = 1

    assert_equal true, @cfg.really_verbose
  end

  def test_write
    @cfg.backtrace = true
    @cfg.benchmark = true
    @cfg.update_sources = false
    @cfg.bulk_threshold = 10
    @cfg.verbose = false
    Gem.sources.replace %w[http://more-gems.example.com]
    @cfg[:install] = '--wrappers'

    @cfg.write

    util_config_file

    # These should not be written out to the config file.
    assert_equal false, @cfg.backtrace,     'backtrace'
    assert_equal false, @cfg.benchmark,     'benchmark'
    assert_equal Gem::ConfigFile::DEFAULT_BULK_THRESHOLD, @cfg.bulk_threshold,
                 'bulk_threshold'
    assert_equal true, @cfg.update_sources, 'update_sources'
    assert_equal true, @cfg.verbose,        'verbose'

    assert_equal '--wrappers', @cfg[:install], 'install'

    # this should be written out to the config file.
    assert_equal %w[http://more-gems.example.com], Gem.sources
  end

  def test_write_from_hash
    File.open @temp_conf, 'w' do |fp|
      fp.puts ":backtrace: true"
      fp.puts ":benchmark: true"
      fp.puts ":bulk_threshold: 10"
      fp.puts ":update_sources: false"
      fp.puts ":verbose: false"
      fp.puts ":sources:"
      fp.puts "  - http://more-gems.example.com"
      fp.puts "install: --wrappers"
    end

    util_config_file

    @cfg.backtrace = :junk
    @cfg.benchmark = :junk
    @cfg.update_sources = :junk
    @cfg.bulk_threshold = 20
    @cfg.verbose = :junk
    Gem.sources.replace %w[http://even-more-gems.example.com]
    @cfg[:install] = '--wrappers --no-rdoc'

    @cfg.write

    util_config_file

    # These should not be written out to the config file
    assert_equal true,  @cfg.backtrace,      'backtrace'
    assert_equal true,  @cfg.benchmark,      'benchmark'
    assert_equal 10,    @cfg.bulk_threshold, 'bulk_threshold'
    assert_equal false, @cfg.update_sources, 'update_sources'
    assert_equal false, @cfg.verbose,        'verbose'

    assert_equal '--wrappers --no-rdoc', @cfg[:install], 'install'

    assert_equal %w[http://even-more-gems.example.com], Gem.sources
  end

  def util_config_file(args = @cfg_args)
    @cfg = Gem::ConfigFile.new args
  end

end

