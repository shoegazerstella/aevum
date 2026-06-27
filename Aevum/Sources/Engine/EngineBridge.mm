// EngineBridge.mm — Obj-C++ implementation wrapping RealtimeRunner.
// All C++ types live here; the header is pure Obj-C for Swift consumption.

#import "EngineBridge.h"
#include <magentart/realtime_runner.h>

#include <memory>
#include <vector>

using magentart::core::RealtimeRunner;
using magentart::core::EngineMetrics;
using magentart::core::kMaxPrompts;
using magentart::core::kMaxPCAComponents;
using magentart::core::kMusicCoCaEmbeddingDim;

@interface EngineBridge () {
    std::unique_ptr<RealtimeRunner> _runner;
}
@end

@implementation EngineBridge

- (instancetype)init {
    self = [super init];
    if (self) {
        _runner = std::make_unique<RealtimeRunner>();
    }
    return self;
}

- (void)dealloc {
    if (_runner) {
        _runner->stop();
        _runner->unload();
    }
}

// MARK: - Lifecycle

- (BOOL)initAssets:(NSString *)resourceDir {
    return _runner ? _runner->init_assets(resourceDir.UTF8String) : NO;
}

- (BOOL)loadModel:(NSString *)mlxfnPath {
    return _runner ? _runner->load_model(mlxfnPath.UTF8String) : NO;
}

- (BOOL)loadPrefillModel:(NSString *)spectrostreamPath
              prefillPath:(nullable NSString *)prefillPath {
    return _runner ? _runner->load_prefill_model(spectrostreamPath.UTF8String,
                                                 prefillPath ? prefillPath.UTF8String : nullptr) : NO;
}

- (BOOL)isLoaded {
    return _runner && _runner->is_loaded();
}

- (void)start { if (_runner) _runner->start(); }
- (void)stop  { if (_runner) _runner->stop(); }
- (void)unload { if (_runner) _runner->unload(); }

// MARK: - Audio output

- (BOOL)readAudioStereoL:(float *)destL R:(float *)destR count:(NSUInteger)count {
    if (!_runner) return NO;
    return _runner->read_audio_stereo(destL, destR, count, /*blocking=*/false);
}

- (BOOL)readAudioStereoBlockingL:(float *)destL R:(float *)destR count:(NSUInteger)count {
    if (!_runner) return NO;
    return _runner->read_audio_stereo(destL, destR, count, /*blocking=*/true);
}

// MARK: - Prompts

- (void)setTextPrompt:(NSString *)text {
    if (_runner) _runner->set_text_prompt(text.UTF8String);
}

- (void)setTextPrompts:(NSArray<NSString *> *)texts weights:(NSArray<NSNumber *> *)weights {
    if (!_runner || texts.count != weights.count) return;
    std::vector<std::string> t;
    std::vector<float> w;
    t.reserve(texts.count);
    w.reserve(weights.count);
    for (NSUInteger i = 0; i < texts.count; ++i) {
        t.emplace_back(texts[i].UTF8String);
        w.push_back(weights[i].floatValue);
    }
    _runner->set_text_prompts(t, w);
}

- (void)setAudioPromptSamplesForIndex:(int)index
                             filename:(NSString *)filename
                              samples:(const float *)samples
                                count:(NSUInteger)count {
    if (_runner) _runner->set_audio_prompt_samples(index, filename.UTF8String,
                                                   samples, count);
}

- (void)setAudioEmbeddingForIndex:(int)index embedding:(const float *)embedding {
    if (_runner) _runner->set_audio_embedding(index, embedding);
}

- (BOOL)getAudioEmbeddingForIndex:(int)index out:(float *)out {
    return _runner && _runner->get_audio_embedding(index, out);
}

- (BOOL)encodeAudioPromptSync:(const float *)samples
                        count:(NSUInteger)count
                          out:(float *)out {
    return _runner && _runner->encode_audio_prompt_sync(samples, count, out);
}

- (XFPromptStatus)textEncoderStatus {
    return (XFPromptStatus)(_runner ? _runner->get_text_encoder_status() : 0);
}

- (XFPromptStatus)promptStatusForIndex:(int)index {
    return (XFPromptStatus)(_runner ? _runner->get_prompt_status(index) : 0);
}

- (XFPromptStatus)quantizerStatus {
    return (XFPromptStatus)(_runner ? _runner->get_quantizer_status() : 0);
}

- (nullable NSString *)cachedTextForIndex:(int)index {
    if (!_runner) return nil;
    auto s = _runner->get_cached_text(index);
    return s.empty() ? nil : [NSString stringWithUTF8String:s.c_str()];
}

- (int)activePromptCount {
    if (!_runner) return 0;
    int active = 0;
    for (int i = 0; i < (int)kMaxPrompts; ++i) {
        if (_runner->get_prompt_status(i) != XFPromptStatusIdle) ++active;
    }
    return active;
}

- (int)rvqDepth {
    // RealtimeRunner doesn't expose rvq_depth directly; the model constant is 12.
    return 12;
}

// MARK: - Blend weights

- (void)setBlendWeightForIndex:(int)index weight:(float)weight {
    if (_runner) _runner->set_blend_weight(index, weight);
}

- (float)blendWeightForIndex:(int)index {
    return _runner ? _runner->get_blend_weight(index) : 0.0f;
}

- (void)setBlendWeights:(const float *)weights count:(int)count {
    if (_runner) _runner->set_blend_weights(weights, count);
}

- (BOOL)reblendMusiccocaTokensWithWeights:(const float *)weights
                                    count:(int)count
                              pcaCoeffs:(const float *)pcaCoeffs
                              pcaCount:(int)pcaCount {
    return _runner && _runner->reblend_musiccoca_tokens(weights, count,
                                                        pcaCoeffs, pcaCount);
}

// MARK: - PCA corpus

- (BOOL)loadPcaFile:(NSString *)path {
    return _runner && _runner->load_pca_file(path.UTF8String);
}

- (BOOL)isPcaLoaded {
    return _runner && _runner->is_pca_loaded();
}

- (int)pcaComponentCount {
    return _runner ? _runner->pca_component_count() : 0;
}

- (int)pcaCentroidCount {
    return _runner ? _runner->pca_centroid_count() : 0;
}

- (void)setPcaCoeffForIndex:(int)index value:(float)value {
    if (_runner) _runner->set_pca_coeff(index, value);
}

- (float)pcaCoeffForIndex:(int)index {
    return _runner ? _runner->get_pca_coeff(index) : 0.0f;
}

// MARK: - Sampling parameters

- (void)setTemperature:(float)t { if (_runner) _runner->set_temperature(t); }
- (float)temperature { return _runner ? _runner->get_temperature() : 1.0f; }
- (void)setTopK:(int)k { if (_runner) _runner->set_top_k(k); }
- (int)topK { return _runner ? _runner->get_top_k() : 100; }
- (void)setCfgMusiccoca:(float)v { if (_runner) _runner->set_cfg_musiccoca(v); }
- (float)cfgMusiccoca { return _runner ? _runner->get_cfg_musiccoca() : 3.0f; }
- (void)setCfgNotes:(float)v { if (_runner) _runner->set_cfg_notes(v); }
- (float)cfgNotes { return _runner ? _runner->get_cfg_notes() : 5.0f; }
- (void)setCfgDrums:(float)v { if (_runner) _runner->set_cfg_drums(v); }
- (float)cfgDrums { return _runner ? _runner->get_cfg_drums() : 1.0f; }
- (void)setUnmaskWidth:(int)w { if (_runner) _runner->set_unmask_width(w); }
- (int)unmaskWidth { return _runner ? _runner->get_unmask_width() : 0; }
- (void)setSeedRotation:(int)r { if (_runner) _runner->set_seed_rotation(r); }
- (int)seedRotation { return _runner ? _runner->get_seed_rotation() : 0; }

// MARK: - MIDI notes

- (void)setNoteOn:(int)n { if (_runner) _runner->set_note_on(n); }
- (void)setNoteOff:(int)n { if (_runner) _runner->set_note_off(n); }

- (void)setOnsetMode:(XFOnsetMode)mode {
    if (_runner) _runner->set_onset_mode((int)mode);
}
- (XFOnsetMode)onsetMode {
    return (XFOnsetMode)(_runner ? _runner->get_onset_mode() : 0);
}

- (void)setDrumless:(BOOL)on { if (_runner) _runner->set_drumless(on); }
- (BOOL)drumless { return _runner && _runner->get_drumless(); }

- (void)setMidiGateEnabled:(BOOL)enabled { if (_runner) _runner->set_midi_gate_enabled(enabled); }
- (BOOL)midiGateEnabled { return _runner && _runner->get_midi_gate_enabled(); }

// MARK: - Output control

- (void)setVolumeDb:(float)v { if (_runner) _runner->set_volume_db(v); }
- (float)volumeDb { return _runner ? _runner->get_volume_db() : 0.0f; }
- (void)setMute:(BOOL)m { if (_runner) _runner->set_mute(m); }
- (BOOL)mute { return _runner && _runner->get_mute(); }
- (void)setLatencyComp:(BOOL)c { if (_runner) _runner->set_latency_comp(c); }
- (BOOL)latencyComp { return _runner && _runner->get_latency_comp(); }
- (void)setBypass:(BOOL)b { if (_runner) _runner->set_bypass(b); }
- (BOOL)bypass { return _runner && _runner->get_bypass(); }
- (void)setBufferSize:(NSUInteger)cap { if (_runner) _runner->set_buffer_size(cap); }
- (NSUInteger)bufferSize { return _runner ? _runner->get_buffer_size() : 0; }
- (NSUInteger)latencySamples { return _runner ? _runner->get_latency_samples() : 0; }

// MARK: - Reset & prefill

- (void)triggerReset { if (_runner) _runner->trigger_reset(); }
- (void)triggerTransportReset { if (_runner) _runner->trigger_transport_reset(); }
- (void)resetForPlayback { if (_runner) _runner->reset_for_playback(); }
- (void)reset { if (_runner) _runner->reset(); }

- (BOOL)prefillStateWithSamples:(const float *)samples
                     sampleCount:(int)sampleCount
                     logCallback:(XFLogCallback)logCallback {
    if (!_runner) return NO;
    std::function<void(const std::string&)> cb;
    if (logCallback) {
        cb = [logCallback](const std::string &msg) {
            logCallback([NSString stringWithUTF8String:msg.c_str()]);
        };
    }
    return _runner->prefill_state(samples, sampleCount, cb);
}

- (BOOL)prefillStateWithSamples:(const float *)samples
                     sampleCount:(int)sampleCount
                     trimFrontFrames:(int)trimFrontFrames
                     trimBackFrames:(int)trimBackFrames
                     logCallback:(XFLogCallback)logCallback {
    if (!_runner) return NO;
    std::function<void(const std::string&)> cb;
    if (logCallback) {
        cb = [logCallback](const std::string &msg) {
            logCallback([NSString stringWithUTF8String:msg.c_str()]);
        };
    }
    return _runner->prefill_state(samples, sampleCount, trimFrontFrames,
                                  trimBackFrames, cb);
}

- (BOOL)prefillSilenceWithDurationFrames:(int)durationFrames
                           logCallback:(XFLogCallback)logCallback {
    if (!_runner) return NO;
    std::function<void(const std::string&)> cb;
    if (logCallback) {
        cb = [logCallback](const std::string &msg) {
            logCallback([NSString stringWithUTF8String:msg.c_str()]);
        };
    }
    return _runner->prefill_silence(durationFrames, cb);
}

// MARK: - State persistence

- (BOOL)saveStateToPath:(NSString *)path {
    return _runner && _runner->save_state(path.UTF8String);
}
- (BOOL)loadStateFromPath:(NSString *)path {
    return _runner && _runner->load_state(path.UTF8String);
}
- (void)resetToFactory { if (_runner) _runner->reset_to_factory(); }

// MARK: - Recording

- (void)startRecording { if (_runner) _runner->start_recording(); }
- (void)stopRecording { if (_runner) _runner->stop_recording(); }
- (void)clearRecording { if (_runner) _runner->clear_recording(); }
- (NSUInteger)recordedSampleCount {
    return _runner ? _runner->get_recorded_sample_count() : 0;
}
- (BOOL)getRecordedAudioL:(float *)destL R:(float *)destR
                startIdx:(NSUInteger)startIdx
                  count:(NSUInteger)count {
    return _runner && _runner->get_recorded_audio(destL, destR, startIdx, count);
}
- (NSArray<NSNumber *> *)waveformPeaksForBuckets:(int)numBuckets {
    if (!_runner || numBuckets <= 0) return @[];
    auto peaks = _runner->get_waveform_peaks(numBuckets);
    NSMutableArray<NSNumber *> *out = [NSMutableArray arrayWithCapacity:peaks.size()];
    for (float p : peaks) [out addObject:@(p)];
    return out;
}

// MARK: - Metrics

- (XFEngineMetrics)metrics {
    XFEngineMetrics m = {0, 0, 0, 0, -1, 0};
    if (!_runner) return m;
    EngineMetrics em = _runner->get_metrics();
    m.transformerMs = em.transformer_ms;
    m.totalMs = em.total_ms;
    m.bufferAvailable = em.buffer_available;
    m.bufferCapacity = em.buffer_capacity;
    m.transportFlags = em.transport_flags;
    m.droppedFrames = em.dropped_frames;
    return m;
}

- (void)resetDroppedFrames { if (_runner) _runner->reset_dropped_frames(); }

// MARK: - Transport / offline

- (void)setTransportFlags:(int)flags { if (_runner) _runner->set_transport_flags(flags); }
- (void)setOffline:(BOOL)offline { if (_runner) _runner->set_offline(offline); }

@end
