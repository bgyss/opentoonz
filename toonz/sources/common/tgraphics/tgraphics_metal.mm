#include "tgraphics.h"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <string>

namespace TGraphics {
namespace {

struct MetalState {
  id<MTLDevice> m_device = nil;
  id<MTLCommandQueue> m_commandQueue = nil;
  std::string m_deviceName;

  MetalState() {
    m_device = MTLCreateSystemDefaultDevice();
    if (!m_device) return;

    m_commandQueue       = [m_device newCommandQueue];
    const char *nameUtf8 = [[m_device name] UTF8String];
    m_deviceName         = nameUtf8 ? nameUtf8 : "";
  }

  ~MetalState() {
#if !__has_feature(objc_arc)
    [m_commandQueue release];
    [m_device release];
#endif
  }
};

MetalState &metalState() {
  static MetalState state;
  return state;
}

}  // namespace

bool probeMetalDevice() {
  MetalState &state = metalState();
  return state.m_device && state.m_commandQueue;
}

const char *probeMetalDeviceName() {
  MetalState &state = metalState();
  return probeMetalDevice() ? state.m_deviceName.c_str() : "";
}

}  // namespace TGraphics
