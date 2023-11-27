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

#include <simobject.h>
#include "pipeline.h"
#include "cache_sim.h"
<<<<<<< HEAD
=======
#include "tex_unit.h"
#include "raster_unit.h"
#include "rop_unit.h"
>>>>>>> 47b5f0545a5746524287aeb535791edc465b295b

namespace vortex {

class Core;

class ExeUnit : public SimObject<ExeUnit> {
public:
    std::vector<SimPort<pipeline_trace_t*>> Inputs;
    std::vector<SimPort<pipeline_trace_t*>> Outputs;

    ExeUnit(const SimContext& ctx, Core* core, const char* name) 
        : SimObject<ExeUnit>(ctx, name) 
        , Inputs(ISSUE_WIDTH, this)
        , Outputs(ISSUE_WIDTH, this)
        , core_(core)
    {}
    
    virtual ~ExeUnit() {}

    virtual void reset() {}

    virtual void tick() = 0;

protected:
    Core* core_;
};

///////////////////////////////////////////////////////////////////////////////

<<<<<<< HEAD
class AluUnit : public ExeUnit {
public:
    AluUnit(const SimContext& ctx, Core*);
    
    void tick();
};

///////////////////////////////////////////////////////////////////////////////

class FpuUnit : public ExeUnit {
public:
    FpuUnit(const SimContext& ctx, Core*);
    
    void tick();
};

///////////////////////////////////////////////////////////////////////////////

=======
>>>>>>> 47b5f0545a5746524287aeb535791edc465b295b
class LsuUnit : public ExeUnit {
public:
    LsuUnit(const SimContext& ctx, Core*);

    void reset();

    void tick();

private:    
    struct pending_req_t {
      pipeline_trace_t* trace;
      uint32_t count;
    };
    HashTable<pending_req_t> pending_rd_reqs_;    
    uint32_t num_lanes_;
    pipeline_trace_t* fence_state_;
    uint64_t pending_loads_;
    bool fence_lock_;
    uint32_t input_idx_;
};

///////////////////////////////////////////////////////////////////////////////

<<<<<<< HEAD
=======
class AluUnit : public ExeUnit {
public:
    AluUnit(const SimContext& ctx, Core*);
    
    void tick();
};

///////////////////////////////////////////////////////////////////////////////

class FpuUnit : public ExeUnit {
public:
    FpuUnit(const SimContext& ctx, Core*);
    
    void tick();
};

///////////////////////////////////////////////////////////////////////////////

>>>>>>> 47b5f0545a5746524287aeb535791edc465b295b
class SfuUnit : public ExeUnit {
public:
    SfuUnit(const SimContext& ctx, Core*);
    
    void tick();

<<<<<<< HEAD
private:
=======
private:    
  std::vector<RasterUnit::Ptr> raster_units_;  
  std::vector<RopUnit::Ptr>    rop_units_;
  std::vector<TexUnit::Ptr>    tex_units_;
  std::vector<SimPort<pipeline_trace_t*>*> pending_rsps_;
>>>>>>> 47b5f0545a5746524287aeb535791edc465b295b
  uint32_t input_idx_;
};

}