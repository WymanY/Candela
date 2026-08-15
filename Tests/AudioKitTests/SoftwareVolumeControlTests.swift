import CoreAudio
import XCTest
@testable import AudioKit

final class SoftwareVolumeControlTests: XCTestCase {
    func testPassthroughOnlyAtFullUnmuted() {
        XCTAssertTrue(SoftwareVolumeControl.shouldPassthrough(volume: 1, muted: false))
        XCTAssertTrue(SoftwareVolumeControl.shouldPassthrough(volume: 0.999, muted: false))
        XCTAssertFalse(SoftwareVolumeControl.shouldPassthrough(volume: 0.99, muted: false))
        XCTAssertFalse(SoftwareVolumeControl.shouldPassthrough(volume: 1, muted: true))
    }

    func testGainIsQuadraticAndMutesToZero() {
        XCTAssertEqual(SoftwareVolumeControl.gain(volume: 0, muted: false), 0)
        XCTAssertEqual(SoftwareVolumeControl.gain(volume: 1, muted: false), 1)
        XCTAssertEqual(SoftwareVolumeControl.gain(volume: 0.5, muted: false), 0.25, accuracy: 0.0001)
        XCTAssertEqual(SoftwareVolumeControl.gain(volume: 0.5, muted: true), 0)
        XCTAssertEqual(SoftwareVolumeControl.gain(volume: .nan, muted: false), 0)
    }

    func testMixScalesSamplesAndZerosWhenMuted() {
        var inputSamples: [Float32] = [0.5, -0.5, 0.25, -0.25]
        var outputSamples: [Float32] = [9, 9, 9, 9]
        inputSamples.withUnsafeMutableBufferPointer { inBuf in
            outputSamples.withUnsafeMutableBufferPointer { outBuf in
                var inBuffer = AudioBuffer(
                    mNumberChannels: 2,
                    mDataByteSize: 16,
                    mData: UnsafeMutableRawPointer(inBuf.baseAddress)
                )
                var outBuffer = AudioBuffer(
                    mNumberChannels: 2,
                    mDataByteSize: 16,
                    mData: UnsafeMutableRawPointer(outBuf.baseAddress)
                )
                var inList = AudioBufferList(mNumberBuffers: 1, mBuffers: inBuffer)
                var outList = AudioBufferList(mNumberBuffers: 1, mBuffers: outBuffer)
                withUnsafePointer(to: &inList) { inPtr in
                    withUnsafeMutablePointer(to: &outList) { outPtr in
                        SoftwareVolumeControl.mix(input: inPtr, output: outPtr, gain: 0.5)
                    }
                }
            }
        }
        XCTAssertEqual(outputSamples[0], 0.25, accuracy: 0.0001)
        XCTAssertEqual(outputSamples[1], -0.25, accuracy: 0.0001)

        outputSamples = [9, 9, 9, 9]
        inputSamples.withUnsafeMutableBufferPointer { inBuf in
            outputSamples.withUnsafeMutableBufferPointer { outBuf in
                var inBuffer = AudioBuffer(
                    mNumberChannels: 2,
                    mDataByteSize: 16,
                    mData: UnsafeMutableRawPointer(inBuf.baseAddress)
                )
                var outBuffer = AudioBuffer(
                    mNumberChannels: 2,
                    mDataByteSize: 16,
                    mData: UnsafeMutableRawPointer(outBuf.baseAddress)
                )
                var inList = AudioBufferList(mNumberBuffers: 1, mBuffers: inBuffer)
                var outList = AudioBufferList(mNumberBuffers: 1, mBuffers: outBuffer)
                withUnsafePointer(to: &inList) { inPtr in
                    withUnsafeMutablePointer(to: &outList) { outPtr in
                        SoftwareVolumeControl.mix(input: inPtr, output: outPtr, gain: 0)
                    }
                }
            }
        }
        XCTAssertEqual(outputSamples, [0, 0, 0, 0])
    }
}
