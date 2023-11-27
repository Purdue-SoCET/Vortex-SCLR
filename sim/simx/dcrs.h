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

#include <util.h>
<<<<<<< HEAD
#include <VX_types.h>
#include <array>
=======
#include "tex_unit.h"
#include "raster_unit.h"
#include "rop_unit.h"
>>>>>>> 47b5f0545a5746524287aeb535791edc465b295b

namespace vortex {

class BaseDCRS {
public:
    uint32_t read(uint32_t addr) const {
        uint32_t state = VX_DCR_BASE_STATE(addr);
        return states_.at(state);
    }

    void write(uint32_t addr, uint32_t value) {
        uint32_t state = VX_DCR_BASE_STATE(addr);
        states_.at(state) = value;
    }

private:    
    std::array<uint32_t, VX_DCR_BASE_STATE_COUNT> states_;
};

class DCRS {
public:
    void write(uint32_t addr, uint32_t value);
    
<<<<<<< HEAD
    BaseDCRS base_dcrs;
=======
    BaseDCRS         base_dcrs;
    TexUnit::DCRS    tex_dcrs;
    RasterUnit::DCRS raster_dcrs;
    RopUnit::DCRS    rop_dcrs;
>>>>>>> 47b5f0545a5746524287aeb535791edc465b295b
};

}