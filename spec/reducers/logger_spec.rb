require 'reducers'

module Reducers
  RSpec.describe Logger do
    it 'is set up with a default logger' do
      expect(subject.info_logger).to eq Logger::ConsoleLogger
      expect(subject.warn_logger).to eq Logger::ConsoleLogger
      expect(subject.error_logger).to eq Logger::ConsoleLogger
    end

    describe '#warn' do
      it 'emits a warning log message' do
        subject.warn_logger = spy
        subject.warn('foo')
        expect(subject.warn_logger).to have_received(:log).with('WARNING: foo')
      end
    end

    describe '#info' do
      it 'emits an info log message' do
        subject.info_logger = spy
        subject.info('foo')
        expect(subject.info_logger).to have_received(:log).with('INFO: foo')
      end
    end

    describe '#error' do
      it 'emits an error log message' do
        subject.error_logger = spy
        subject.error('foo')
        expect(subject.error_logger).to have_received(:log).with('ERROR: foo')
      end
    end

    describe '#silence' do
      it 'sets all loggers to NullLogger with the block' do
        subject.silence do
          expect(subject.error_logger).to eq Logger::NullLogger
          expect(subject.warn_logger).to eq Logger::NullLogger
          expect(subject.info_logger).to eq Logger::NullLogger
        end
        expect(subject.error_logger).not_to eq Logger::NullLogger
        expect(subject.warn_logger).not_to eq Logger::NullLogger
        expect(subject.info_logger).not_to eq Logger::NullLogger
      end
    end
  end

  RSpec.describe Logger::ConsoleLogger do
    describe '::log' do
      it 'writes a message to the given IO-like object' do
        io = StringIO.new
        described_class.log('foo', io)
        expect(io.tap(&:rewind).read.chomp).to eq 'foo'
      end
    end
  end
end
