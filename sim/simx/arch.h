// Copyright © 2019-2023
// 
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
// 
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#pragma once

#include <string>
#include <sstream>

#include <cstdlib>
#include <stdio.h>
#include "types.h"

namespace vortex {

class Arch {  
private:
  uint16_t num_threads_;
  uint16_t num_warps_;
  uint16_t num_cores_;  
  uint16_t num_clusters_;  
  uint16_t vsize_;
  uint16_t num_regs_;
  uint16_t num_csrs_;
  uint16_t num_barriers_;
  uint16_t ipdom_size_;
  
public:
  Arch(uint16_t num_threads, uint16_t num_warps, uint16_t num_cores, uint16_t num_clusters)   
    : num_threads_(num_threads)
    , num_warps_(num_warps)
    , num_cores_(num_cores)
    , num_clusters_(num_clusters)
    , vsize_(16)
    , num_regs_(32)
    , num_csrs_(4096)
    , num_barriers_(NUM_BARRIERS)
    , ipdom_size_((num_threads-1) * 2)
  {}

  uint16_t vsize() const { 
    return vsize_; 
  }

  uint16_t num_regs() const {
    return num_regs_;
  }

  uint16_t num_csrs() const {
    return num_csrs_;
  }

  uint16_t num_barriers() const {
    return num_barriers_;
  }

  uint16_t ipdom_size() const {
    return ipdom_size_;
  }

  uint16_t num_threads() const {
    return num_threads_;
  }

  uint16_t num_warps() const {
    return num_warps_;
  }

  uint16_t num_cores() const {
    return num_cores_;
  }
  
  uint16_t num_clusters() const {
    return num_clusters_;
  }
};

}