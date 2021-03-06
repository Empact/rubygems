require 'fileutils'
require 'tmpdir'
require 'zlib'

require 'rubygems'
require 'rubygems/format'

begin
  require 'builder/xchar'
rescue LoadError
end

##
# Top level class for building the gem repository index.

class Gem::Indexer

  include Gem::UserInteraction

  ##
  # Build indexes for RubyGems older than 1.2.0 when true

  attr_accessor :build_legacy

  ##
  # Build indexes for RubyGems 1.2.0 and newer when true

  attr_accessor :build_modern

  ##
  # Index install location

  attr_reader :dest_directory

  ##
  # Specs index install location

  attr_reader :dest_specs_index

  ##
  # Latest specs index install location

  attr_reader :dest_latest_specs_index

  ##
  # Index build directory

  attr_reader :directory

  ##
  # Create an indexer that will index the gems in +directory+.

  def initialize(directory, options = {})
    unless ''.respond_to? :to_xs then
      fail "Gem::Indexer requires that the XML Builder library be installed:" \
           "\n\tgem install builder"
    end

    options = { :build_legacy => true, :build_modern => true }.merge options

    @build_legacy = options[:build_legacy]
    @build_modern = options[:build_modern]

    @dest_directory = directory
    @directory = File.join Dir.tmpdir, "gem_generate_index_#{$$}"

    marshal_name = "Marshal.#{Gem.marshal_version}"

    @master_index = File.join @directory, 'yaml'
    @marshal_index = File.join @directory, marshal_name

    @quick_dir = File.join @directory, 'quick'

    @quick_marshal_dir = File.join @quick_dir, marshal_name

    @quick_index = File.join @quick_dir, 'index'
    @latest_index = File.join @quick_dir, 'latest_index'

    @specs_index = File.join @directory, "specs.#{Gem.marshal_version}"
    @latest_specs_index = File.join @directory,
                                    "latest_specs.#{Gem.marshal_version}"

    @dest_specs_index = File.join @dest_directory,
                                  "specs.#{Gem.marshal_version}"
    @dest_latest_specs_index = File.join @dest_directory,
                                         "latest_specs.#{Gem.marshal_version}"

    @files = []
  end

  ##
  # Abbreviate the spec for downloading.  Abbreviated specs are only used for
  # searching, downloading and related activities and do not need deployment
  # specific information (e.g. list of files).  So we abbreviate the spec,
  # making it much smaller for quicker downloads.

  def abbreviate(spec)
    spec.files = []
    spec.test_files = []
    spec.rdoc_options = []
    spec.extra_rdoc_files = []
    spec.cert_chain = []
    spec
  end

  ##
  # Build various indicies

  def build_indicies(index)
    # Marshal gemspecs are used by both modern and legacy RubyGems
    build_marshal_gemspecs index
    build_legacy_indicies index if @build_legacy
    build_modern_indicies index if @build_modern

    compress_indicies
  end

  ##
  # Builds indicies for RubyGems older than 1.2.x

  def build_legacy_indicies(index)
    progress = ui.progress_reporter index.size,
                                    "Generating YAML quick index gemspecs for #{index.size} gems",
                                    "Complete"

    Gem.time 'Generated YAML quick index gemspecs' do
      index.each do |original_name, spec|
        spec_file_name = "#{original_name}.gemspec.rz"
        yaml_name = File.join @quick_dir, spec_file_name

        yaml_zipped = Gem.deflate spec.to_yaml
        open yaml_name, 'wb' do |io| io.write yaml_zipped end

        progress.updated original_name
      end

      progress.done
    end

    say "Generating quick index"

    Gem.time 'Generated quick index' do
      open @quick_index, 'wb' do |io|
        io.puts index.sort.map { |_, spec| spec.original_name }
      end
    end

    say "Generating latest index"

    Gem.time 'Generated latest index' do
      open @latest_index, 'wb' do |io|
        io.puts index.latest_specs.sort.map { |spec| spec.original_name }
      end
    end

    say "Generating Marshal master index"

    Gem.time 'Generated Marshal master index' do
      open @marshal_index, 'wb' do |io|
        io.write index.dump
      end
    end

    progress = ui.progress_reporter index.size,
                                    "Generating YAML master index for #{index.size} gems (this may take a while)",
                                    "Complete"

    Gem.time 'Generated YAML master index' do
      open @master_index, 'wb' do |io|
        io.puts "--- !ruby/object:#{index.class}"
        io.puts "gems:"

        gems = index.sort_by { |name, gemspec| gemspec.sort_obj }
        gems.each do |original_name, gemspec|
          yaml = gemspec.to_yaml.gsub(/^/, '    ')
          yaml = yaml.sub(/\A    ---/, '') # there's a needed extra ' ' here
          io.print "  #{original_name}:"
          io.puts yaml

          progress.updated original_name
        end
      end

      progress.done
    end

    @files << @quick_dir
    @files << @master_index
    @files << "#{@master_index}.Z"
    @files << @marshal_index
    @files << "#{@marshal_index}.Z"
  end

  ##
  # Builds Marshal quick index gemspecs.

  def build_marshal_gemspecs(index)
    progress = ui.progress_reporter index.size,
                                    "Generating Marshal quick index gemspecs for #{index.size} gems",
                                    "Complete"

    files = []

    Gem.time 'Generated Marshal quick index gemspecs' do
      index.each do |original_name, spec|
        spec_file_name = "#{original_name}.gemspec.rz"
        marshal_name = File.join @quick_marshal_dir, spec_file_name

        marshal_zipped = Gem.deflate Marshal.dump(spec)
        open marshal_name, 'wb' do |io| io.write marshal_zipped end

        files << marshal_name

        progress.updated original_name
      end

      progress.done
    end

    @files << @quick_marshal_dir

    files
  end

  ##
  # Builds indicies for RubyGems 1.2 and newer

  def build_modern_indicies(index)
    say "Generating specs index"

    Gem.time 'Generated specs index' do
      open @specs_index, 'wb' do |io|
        specs = index.sort.map do |_, spec|
          platform = spec.original_platform
          platform = Gem::Platform::RUBY if platform.nil? or platform.empty?
          [spec.name, spec.version, platform]
        end

        specs = compact_specs specs

        Marshal.dump specs, io
      end
    end

    say "Generating latest specs index"

    Gem.time 'Generated latest specs index' do
      open @latest_specs_index, 'wb' do |io|
        specs = index.latest_specs.sort.map do |spec|
          platform = spec.original_platform
          platform = Gem::Platform::RUBY if platform.nil? or platform.empty?
          [spec.name, spec.version, platform]
        end

        specs = compact_specs specs

        Marshal.dump specs, io
      end
    end

    @files << @specs_index
    @files << "#{@specs_index}.gz"
    @files << @latest_specs_index
    @files << "#{@latest_specs_index}.gz"
  end

  ##
  # Collect specifications from .gem files from the gem directory.

  def collect_specs(gems = gem_file_list)
    index = Gem::SourceIndex.new

    progress = ui.progress_reporter gems.size,
                                    "Loading #{gems.size} gems from #{@dest_directory}",
                                    "Loaded all gems"

    Gem.time 'loaded' do
      gems.each do |gemfile|
        if File.size(gemfile.to_s) == 0 then
          alert_warning "Skipping zero-length gem: #{gemfile}"
          next
        end

        begin
          spec = Gem::Format.from_file_by_path(gemfile).spec

          unless gemfile =~ /\/#{Regexp.escape spec.original_name}.*\.gem\z/i then
            alert_warning "Skipping misnamed gem: #{gemfile} => #{spec.full_name} (#{spec.original_name})"
            next
          end

          abbreviate spec
          sanitize spec

          index.gems[spec.original_name] = spec

          progress.updated spec.original_name

        rescue SignalException => e
          alert_error "Received signal, exiting"
          raise
        rescue Exception => e
          alert_error "Unable to process #{gemfile}\n#{e.message} (#{e.class})\n\t#{e.backtrace.join "\n\t"}"
        end
      end

      progress.done
    end

    index
  end

  ##
  # Compresses indicies on disk
  #--
  # All future files should be compressed using gzip, not deflate

  def compress_indicies
    say "Compressing indicies"

    Gem.time 'Compressed indicies' do
      if @build_legacy then
        compress @quick_index, 'rz'
        paranoid @quick_index, 'rz'

        compress @latest_index, 'rz'
        paranoid @latest_index, 'rz'

        compress @marshal_index, 'Z'
        paranoid @marshal_index, 'Z'

        compress @master_index, 'Z'
        paranoid @master_index, 'Z'
      end

      if @build_modern then
        gzip @specs_index
        gzip @latest_specs_index
      end
    end
  end

  ##
  # Compacts Marshal output for the specs index data source by using identical
  # objects as much as possible.

  def compact_specs(specs)
    names = {}
    versions = {}
    platforms = {}

    specs.map do |(name, version, platform)|
      names[name] = name unless names.include? name
      versions[version] = version unless versions.include? version
      platforms[platform] = platform unless platforms.include? platform

      [names[name], versions[version], platforms[platform]]
    end
  end

  ##
  # Compress +filename+ with +extension+.

  def compress(filename, extension)
    data = Gem.read_binary filename

    zipped = Gem.deflate data

    open "#{filename}.#{extension}", 'wb' do |io|
      io.write zipped
    end
  end

  ##
  # List of gem file names to index.

  def gem_file_list
    Dir.glob(File.join(@dest_directory, "gems", "*.gem"))
  end

  ##
  # Builds and installs indexicies.

  def generate_index
    make_temp_directories
    index = collect_specs
    build_indicies index
    install_indicies
  rescue SignalException
  ensure
    FileUtils.rm_rf @directory
  end

   ##
  # Zlib::GzipWriter wrapper that gzips +filename+ on disk.

  def gzip(filename)
    Zlib::GzipWriter.open "#{filename}.gz" do |io|
      io.write Gem.read_binary(filename)
    end
  end

  ##
  # Install generated indicies into the destination directory.

  def install_indicies
    verbose = Gem.configuration.really_verbose

    say "Moving index into production dir #{@dest_directory}" if verbose

    files = @files.dup
    files.delete @quick_marshal_dir if files.include? @quick_dir

    if files.include? @quick_marshal_dir and
       not files.include? @quick_dir then
      files.delete @quick_marshal_dir
      quick_marshal_dir = @quick_marshal_dir.sub @directory, ''

      dst_name = File.join @dest_directory, quick_marshal_dir

      FileUtils.mkdir_p File.dirname(dst_name), :verbose => verbose
      FileUtils.rm_rf dst_name, :verbose => verbose
      FileUtils.mv @quick_marshal_dir, dst_name, :verbose => verbose,
                   :force => true
    end

    files = files.map do |path|
      path.sub @directory, ''
    end

    files.each do |file|
      src_name = File.join @directory, file
      dst_name = File.join @dest_directory, file

      FileUtils.rm_rf dst_name, :verbose => verbose
      FileUtils.mv src_name, @dest_directory, :verbose => verbose,
                   :force => true
    end
  end

  ##
  # Make directories for index generation

  def make_temp_directories
    FileUtils.rm_rf @directory
    FileUtils.mkdir_p @directory, :mode => 0700
    FileUtils.mkdir_p @quick_marshal_dir
  end

  ##
  # Ensure +path+ and path with +extension+ are identical.

  def paranoid(path, extension)
    data = Gem.read_binary path
    compressed_data = Gem.read_binary "#{path}.#{extension}"

    unless data == Gem.inflate(compressed_data) then
      raise "Compressed file #{compressed_path} does not match uncompressed file #{path}"
    end
  end

  ##
  # Sanitize the descriptive fields in the spec.  Sometimes non-ASCII
  # characters will garble the site index.  Non-ASCII characters will
  # be replaced by their XML entity equivalent.

  def sanitize(spec)
    spec.summary = sanitize_string(spec.summary)
    spec.description = sanitize_string(spec.description)
    spec.post_install_message = sanitize_string(spec.post_install_message)
    spec.authors = spec.authors.collect { |a| sanitize_string(a) }

    spec
  end

  ##
  # Sanitize a single string.

  def sanitize_string(string)
    # HACK the #to_s is in here because RSpec has an Array of Arrays of
    # Strings for authors.  Need a way to disallow bad values on gempsec
    # generation.  (Probably won't happen.)
    string ? string.to_s.to_xs : string
  end

  ##
  # Perform an in-place update of the repository from newly added gems.  Only
  # works for modern indicies, and sets #build_legacy to false when run.

  def update_index
    @build_legacy = false

    make_temp_directories

    specs_mtime = File.stat(@dest_specs_index).mtime
    newest_mtime = Time.at 0

    updated_gems = gem_file_list.select do |gem|
      gem_mtime = File.stat(gem).mtime
      newest_mtime = gem_mtime if gem_mtime > newest_mtime
      gem_mtime >= specs_mtime
    end

    if updated_gems.empty? then
      say 'No new gems'
      terminate_interaction 0
    end

    index = collect_specs updated_gems

    files = build_marshal_gemspecs index

    Gem.time 'Updated indexes' do
      update_specs_index index, @dest_specs_index, @specs_index
      update_specs_index index, @dest_latest_specs_index, @latest_specs_index
    end

    compress_indicies

    verbose = Gem.configuration.really_verbose

    say "Updating production dir #{@dest_directory}" if verbose

    files << @specs_index
    files << "#{@specs_index}.gz"
    files << @latest_specs_index
    files << "#{@latest_specs_index}.gz"

    files = files.map do |path|
      path.sub @directory, ''
    end

    files.each do |file|
      src_name = File.join @directory, file
      dst_name = File.join @dest_directory, File.dirname(file)

      FileUtils.mv src_name, dst_name, :verbose => verbose,
                   :force => true

      File.utime newest_mtime, newest_mtime, dst_name
    end
  end

  ##
  # Combines specs in +index+ and +source+ then writes out a new copy to
  # +dest+.  For a latest index, does not ensure the new file is minimal.

  def update_specs_index(index, source, dest)
    specs_index = Marshal.load Gem.read_binary(source)

    index.each do |_, spec|
      platform = spec.original_platform
      platform = Gem::Platform::RUBY if platform.nil? or platform.empty?
      specs_index << [spec.name, spec.version, platform]
    end

    specs_index = compact_specs specs_index.uniq.sort

    open dest, 'wb' do |io|
      Marshal.dump specs_index, io
    end
  end

end

