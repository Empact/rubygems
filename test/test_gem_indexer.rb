#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require File.join(File.expand_path(File.dirname(__FILE__)), 'gemutilities')

require 'rubygems/indexer'

unless ''.respond_to? :to_xs then
  warn "Gem::Indexer tests are being skipped.  Install builder gem."
end

class TestGemIndexer < RubyGemTestCase

  def setup
    super

    util_make_gems

    @d2_0 = quick_gem 'd', '2.0'
    util_build_gem @d2_0

    gems = File.join(@tempdir, 'gems')
    FileUtils.mkdir_p gems
    cache_gems = File.join @gemhome, 'cache', '*.gem'
    FileUtils.mv Dir[cache_gems], gems

    @indexer = Gem::Indexer.new @tempdir
  end

  def test_initialize
    assert_equal @tempdir, @indexer.dest_directory
    assert_equal File.join(Dir.tmpdir, "gem_generate_index_#{$$}"),
                 @indexer.directory

    indexer = Gem::Indexer.new @tempdir
    assert indexer.build_legacy
    assert indexer.build_modern

    indexer = Gem::Indexer.new @tempdir, :build_legacy => false,
                               :build_modern => true
    refute indexer.build_legacy
    assert indexer.build_modern

    indexer = Gem::Indexer.new @tempdir, :build_legacy => true,
                               :build_modern => false
    assert indexer.build_legacy
    refute indexer.build_modern
  end

  def test_build_indicies
    spec = quick_gem 'd', '2.0'
    spec.instance_variable_set :@original_platform, ''

    @indexer.make_temp_directories

    index = Gem::SourceIndex.new
    index.add_spec spec

    use_ui @ui do
      @indexer.build_indicies index
    end

    specs_path = File.join @indexer.directory, "specs.#{@marshal_version}"
    specs_dump = Gem.read_binary specs_path
    specs = Marshal.load specs_dump

    expected = [
      ['d',      Gem::Version.new('2.0'), 'ruby'],
    ]

    assert_equal expected, specs, 'specs'

    latest_specs_path = File.join @indexer.directory,
                                  "latest_specs.#{@marshal_version}"
    latest_specs_dump = Gem.read_binary latest_specs_path
    latest_specs = Marshal.load latest_specs_dump

    expected = [
      ['d',      Gem::Version.new('2.0'), 'ruby'],
    ]

    assert_equal expected, latest_specs, 'latest_specs'
  end

  def test_generate_index
    use_ui @ui do
      @indexer.generate_index
    end

    assert_indexed @tempdir, 'yaml'
    assert_indexed @tempdir, 'yaml.Z'
    assert_indexed @tempdir, "Marshal.#{@marshal_version}"
    assert_indexed @tempdir, "Marshal.#{@marshal_version}.Z"

    quickdir = File.join @tempdir, 'quick'
    marshal_quickdir = File.join quickdir, "Marshal.#{@marshal_version}"

    assert File.directory?(quickdir)
    assert File.directory?(marshal_quickdir)

    assert_indexed quickdir, "index"
    assert_indexed quickdir, "index.rz"

    quick_index = File.read File.join(quickdir, 'index')
    expected = <<-EOF
a-1
a-2
a_evil-9
b-2
c-1.2
d-2.0
pl-1-i386-linux
    EOF

    assert_equal expected, quick_index

    assert_indexed quickdir, "latest_index"
    assert_indexed quickdir, "latest_index.rz"

    latest_quick_index = File.read File.join(quickdir, 'latest_index')
    expected = <<-EOF
a-2
a_evil-9
b-2
c-1.2
d-2.0
pl-1-i386-linux
    EOF

    assert_equal expected, latest_quick_index

    assert_indexed quickdir, "#{@a1.full_name}.gemspec.rz"
    assert_indexed quickdir, "#{@a2.full_name}.gemspec.rz"
    assert_indexed quickdir, "#{@b2.full_name}.gemspec.rz"
    assert_indexed quickdir, "#{@c1_2.full_name}.gemspec.rz"

    assert_indexed quickdir, "#{@pl1.original_name}.gemspec.rz"
    refute_indexed quickdir, "#{@pl1.full_name}.gemspec.rz"

    assert_indexed marshal_quickdir, "#{@a1.full_name}.gemspec.rz"
    assert_indexed marshal_quickdir, "#{@a2.full_name}.gemspec.rz"

    refute_indexed quickdir, "#{@c1_2.full_name}.gemspec"
    refute_indexed marshal_quickdir, "#{@c1_2.full_name}.gemspec"

    assert_indexed @tempdir, "specs.#{@marshal_version}"
    assert_indexed @tempdir, "specs.#{@marshal_version}.gz"

    assert_indexed @tempdir, "latest_specs.#{@marshal_version}"
    assert_indexed @tempdir, "latest_specs.#{@marshal_version}.gz"
  end

  def test_generate_index_legacy
    @indexer.build_modern = false
    @indexer.build_legacy = true

    use_ui @ui do
      @indexer.generate_index
    end

    assert_indexed @tempdir, 'yaml'
    assert_indexed @tempdir, 'yaml.Z'
    assert_indexed @tempdir, "Marshal.#{@marshal_version}"
    assert_indexed @tempdir, "Marshal.#{@marshal_version}.Z"

    quickdir = File.join @tempdir, 'quick'
    marshal_quickdir = File.join quickdir, "Marshal.#{@marshal_version}"

    assert File.directory?(quickdir)
    assert File.directory?(marshal_quickdir)

    assert_indexed quickdir, "index"
    assert_indexed quickdir, "index.rz"

    assert_indexed quickdir, "latest_index"
    assert_indexed quickdir, "latest_index.rz"

    assert_indexed quickdir, "#{@a1.full_name}.gemspec.rz"
    assert_indexed quickdir, "#{@a2.full_name}.gemspec.rz"
    assert_indexed quickdir, "#{@b2.full_name}.gemspec.rz"
    assert_indexed quickdir, "#{@c1_2.full_name}.gemspec.rz"

    assert_indexed quickdir, "#{@pl1.original_name}.gemspec.rz"
    refute_indexed quickdir, "#{@pl1.full_name}.gemspec.rz"

    assert_indexed marshal_quickdir, "#{@a1.full_name}.gemspec.rz"
    assert_indexed marshal_quickdir, "#{@a2.full_name}.gemspec.rz"

    refute_indexed quickdir, "#{@c1_2.full_name}.gemspec"
    refute_indexed marshal_quickdir, "#{@c1_2.full_name}.gemspec"

    refute_indexed @tempdir, "specs.#{@marshal_version}"
    refute_indexed @tempdir, "specs.#{@marshal_version}.gz"

    refute_indexed @tempdir, "latest_specs.#{@marshal_version}"
    refute_indexed @tempdir, "latest_specs.#{@marshal_version}.gz"
  end

  def test_generate_index_legacy_back_to_back
    @indexer.build_modern = true
    @indexer.build_legacy = true

    use_ui @ui do
      @indexer.generate_index
    end

    @indexer = Gem::Indexer.new @tempdir
    @indexer.build_modern = false
    @indexer.build_legacy = true

    use_ui @ui do
      @indexer.generate_index
    end

    assert_indexed @tempdir, 'yaml'
    assert_indexed @tempdir, 'yaml.Z'
    assert_indexed @tempdir, "Marshal.#{@marshal_version}"
    assert_indexed @tempdir, "Marshal.#{@marshal_version}.Z"

    quickdir = File.join @tempdir, 'quick'
    marshal_quickdir = File.join quickdir, "Marshal.#{@marshal_version}"

    assert File.directory?(quickdir)
    assert File.directory?(marshal_quickdir)

    assert_indexed quickdir, "index"
    assert_indexed quickdir, "index.rz"

    assert_indexed quickdir, "latest_index"
    assert_indexed quickdir, "latest_index.rz"

    assert_indexed quickdir, "#{@a1.full_name}.gemspec.rz"
    assert_indexed quickdir, "#{@a2.full_name}.gemspec.rz"
    assert_indexed quickdir, "#{@b2.full_name}.gemspec.rz"
    assert_indexed quickdir, "#{@c1_2.full_name}.gemspec.rz"

    assert_indexed quickdir, "#{@pl1.original_name}.gemspec.rz"

    assert_indexed marshal_quickdir, "#{@a1.full_name}.gemspec.rz"
    assert_indexed marshal_quickdir, "#{@a2.full_name}.gemspec.rz"

    assert_indexed @tempdir, "specs.#{@marshal_version}"
    assert_indexed @tempdir, "specs.#{@marshal_version}.gz"

    assert_indexed @tempdir, "latest_specs.#{@marshal_version}"
    assert_indexed @tempdir, "latest_specs.#{@marshal_version}.gz"
  end

  def test_generate_index_modern
    @indexer.build_modern = true
    @indexer.build_legacy = false

    use_ui @ui do
      @indexer.generate_index
    end

    refute_indexed @tempdir, 'yaml'
    refute_indexed @tempdir, 'yaml.Z'
    refute_indexed @tempdir, "Marshal.#{@marshal_version}"
    refute_indexed @tempdir, "Marshal.#{@marshal_version}.Z"

    quickdir = File.join @tempdir, 'quick'
    marshal_quickdir = File.join quickdir, "Marshal.#{@marshal_version}"

    assert File.directory?(quickdir), 'quickdir should be directory'
    assert File.directory?(marshal_quickdir)

    refute_indexed quickdir, "index"
    refute_indexed quickdir, "index.rz"

    refute_indexed quickdir, "latest_index"
    refute_indexed quickdir, "latest_index.rz"

    refute_indexed quickdir, "#{@a1.full_name}.gemspec.rz"
    refute_indexed quickdir, "#{@a2.full_name}.gemspec.rz"
    refute_indexed quickdir, "#{@b2.full_name}.gemspec.rz"
    refute_indexed quickdir, "#{@c1_2.full_name}.gemspec.rz"

    refute_indexed quickdir, "#{@pl1.original_name}.gemspec.rz"
    refute_indexed quickdir, "#{@pl1.full_name}.gemspec.rz"

    assert_indexed marshal_quickdir, "#{@a1.full_name}.gemspec.rz"
    assert_indexed marshal_quickdir, "#{@a2.full_name}.gemspec.rz"

    refute_indexed quickdir, "#{@c1_2.full_name}.gemspec"
    refute_indexed marshal_quickdir, "#{@c1_2.full_name}.gemspec"

    assert_indexed @tempdir, "specs.#{@marshal_version}"
    assert_indexed @tempdir, "specs.#{@marshal_version}.gz"

    assert_indexed @tempdir, "latest_specs.#{@marshal_version}"
    assert_indexed @tempdir, "latest_specs.#{@marshal_version}.gz"
  end

  def test_generate_index_modern_back_to_back
    @indexer.build_modern = true
    @indexer.build_legacy = true

    use_ui @ui do
      @indexer.generate_index
    end

    @indexer = Gem::Indexer.new @tempdir
    @indexer.build_modern = true
    @indexer.build_legacy = false

    use_ui @ui do
      @indexer.generate_index
    end

    assert_indexed @tempdir, 'yaml'
    assert_indexed @tempdir, 'yaml.Z'
    assert_indexed @tempdir, "Marshal.#{@marshal_version}"
    assert_indexed @tempdir, "Marshal.#{@marshal_version}.Z"

    quickdir = File.join @tempdir, 'quick'
    marshal_quickdir = File.join quickdir, "Marshal.#{@marshal_version}"

    assert File.directory?(quickdir)
    assert File.directory?(marshal_quickdir)

    assert_indexed quickdir, "index"
    assert_indexed quickdir, "index.rz"

    assert_indexed quickdir, "latest_index"
    assert_indexed quickdir, "latest_index.rz"

    assert_indexed quickdir, "#{@a1.full_name}.gemspec.rz"
    assert_indexed quickdir, "#{@a2.full_name}.gemspec.rz"
    assert_indexed quickdir, "#{@b2.full_name}.gemspec.rz"
    assert_indexed quickdir, "#{@c1_2.full_name}.gemspec.rz"

    assert_indexed quickdir, "#{@pl1.original_name}.gemspec.rz"

    assert_indexed marshal_quickdir, "#{@a1.full_name}.gemspec.rz"
    assert_indexed marshal_quickdir, "#{@a2.full_name}.gemspec.rz"

    assert_indexed @tempdir, "specs.#{@marshal_version}"
    assert_indexed @tempdir, "specs.#{@marshal_version}.gz"

    assert_indexed @tempdir, "latest_specs.#{@marshal_version}"
    assert_indexed @tempdir, "latest_specs.#{@marshal_version}.gz"
  end

  def test_generate_index_ui
    use_ui @ui do
      @indexer.generate_index
    end

    assert_match %r%^Loading 7 gems from #{Regexp.escape @tempdir}$%, @ui.output
    assert_match %r%^\.\.\.\.\.\.\.$%, @ui.output
    assert_match %r%^Loaded all gems$%, @ui.output
    assert_match %r%^Generating Marshal quick index gemspecs for 7 gems$%,
                 @ui.output
    assert_match %r%^Generating YAML quick index gemspecs for 7 gems$%,
                 @ui.output
    assert_match %r%^\.\.\.\.\.\.\.$%, @ui.output
    assert_match %r%^Complete$%, @ui.output
    assert_match %r%^Generating specs index$%, @ui.output
    assert_match %r%^Generating latest specs index$%, @ui.output
    assert_match %r%^Generating quick index$%, @ui.output
    assert_match %r%^Generating latest index$%, @ui.output
    assert_match %r%^Generating Marshal master index$%, @ui.output
    assert_match %r%^Generating YAML master index for 7 gems \(this may take a while\)$%, @ui.output
    assert_match %r%^\.\.\.\.\.\.\.$%, @ui.output
    assert_match %r%^Complete$%, @ui.output
    assert_match %r%^Compressing indicies$%, @ui.output

    assert_equal '', @ui.error
  end

  def test_generate_index_master
    use_ui @ui do
      @indexer.generate_index
    end

    yaml_path = File.join @tempdir, 'yaml'
    dump_path = File.join @tempdir, "Marshal.#{@marshal_version}"

    yaml_index = YAML.load_file yaml_path
    dump_index = Marshal.load Gem.read_binary(dump_path)

    dump_index.each do |_,gem|
      gem.send :remove_instance_variable, :@loaded
    end

    assert_equal yaml_index, dump_index,
                 "expected YAML and Marshal to produce identical results"
  end

  def test_generate_index_specs
    use_ui @ui do
      @indexer.generate_index
    end

    specs_path = File.join @tempdir, "specs.#{@marshal_version}"

    specs_dump = Gem.read_binary specs_path
    specs = Marshal.load specs_dump

    expected = [
      ['a',      Gem::Version.new(1),     'ruby'],
      ['a',      Gem::Version.new(2),     'ruby'],
      ['a_evil', Gem::Version.new(9),     'ruby'],
      ['b',      Gem::Version.new(2),     'ruby'],
      ['c',      Gem::Version.new('1.2'), 'ruby'],
      ['d',      Gem::Version.new('2.0'), 'ruby'],
      ['pl',     Gem::Version.new(1),     'i386-linux'],
    ]

    assert_equal expected, specs

    assert_same specs[0].first, specs[1].first,
                'identical names not identical'

    assert_same specs[0][1],    specs[-1][1],
                'identical versions not identical'

    assert_same specs[0].last, specs[1].last,
                'identical platforms not identical'

    refute_same specs[1][1], specs[5][1],
                'different versions not different'
  end

  def test_generate_index_latest_specs
    use_ui @ui do
      @indexer.generate_index
    end

    latest_specs_path = File.join @tempdir, "latest_specs.#{@marshal_version}"

    latest_specs_dump = Gem.read_binary latest_specs_path
    latest_specs = Marshal.load latest_specs_dump

    expected = [
      ['a',      Gem::Version.new(2),     'ruby'],
      ['a_evil', Gem::Version.new(9),     'ruby'],
      ['b',      Gem::Version.new(2),     'ruby'],
      ['c',      Gem::Version.new('1.2'), 'ruby'],
      ['d',      Gem::Version.new('2.0'), 'ruby'],
      ['pl',     Gem::Version.new(1),     'i386-linux'],
    ]

    assert_equal expected, latest_specs

    assert_same latest_specs[0][1],   latest_specs[2][1],
                'identical versions not identical'

    assert_same latest_specs[0].last, latest_specs[1].last,
                'identical platforms not identical'
  end

  def test_update_index
    use_ui @ui do
      @indexer.generate_index
    end

    quickdir = File.join @tempdir, 'quick'
    marshal_quickdir = File.join quickdir, "Marshal.#{@marshal_version}"

    assert File.directory?(quickdir)
    assert File.directory?(marshal_quickdir)

    @d2_1 = quick_gem 'd', '2.1'
    util_build_gem @d2_1

    gems = File.join @tempdir, 'gems'
    FileUtils.mv File.join(@gemhome, 'cache', "#{@d2_1.full_name}.gem"), gems

    use_ui @ui do
      @indexer.update_index
    end

    assert_indexed marshal_quickdir, "#{@d2_1.full_name}.gemspec.rz"

    specs_index = Marshal.load Gem.read_binary(@indexer.dest_specs_index)

    assert_includes specs_index,
                    [@d2_1.name, @d2_1.version, @d2_1.original_platform]
                    
    latest_specs_index = Marshal.load \
      Gem.read_binary(@indexer.dest_latest_specs_index)

    assert_includes latest_specs_index,
                    [@d2_1.name, @d2_1.version, @d2_1.original_platform]
    assert_includes latest_specs_index,
                    [@d2_0.name, @d2_0.version, @d2_0.original_platform]
  end

  def assert_indexed(dir, name)
    file = File.join dir, name
    assert File.exist?(file), "#{file} does not exist"
  end

  def refute_indexed(dir, name)
    file = File.join dir, name
    assert !File.exist?(file), "#{file} exists"
  end

end if ''.respond_to? :to_xs

