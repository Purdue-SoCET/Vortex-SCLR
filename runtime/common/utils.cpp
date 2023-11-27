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

#include "utils.h"
#include <iostream>
#include <fstream>
#include <list>
#include <cstring>
#include <vector>
#include <vortex.h>
#include <assert.h>

#define RT_CHECK(_expr, _cleanup)                               \
   do {                                                         \
     int _ret = _expr;                                          \
     if (0 == _ret)                                             \
       break;                                                   \
     printf("Error: '%s' returned %d!\n", #_expr, (int)_ret);   \
     _cleanup                                                   \
   } while (false)

uint64_t aligned_size(uint64_t size, uint64_t alignment) {        
    assert(0 == (alignment & (alignment - 1)));
    return (size + alignment - 1) & ~(alignment - 1);
}

bool is_aligned(uint64_t addr, uint64_t alignment) {
    assert(0 == (alignment & (alignment - 1)));
    return 0 == (addr & (alignment - 1));
}

///////////////////////////////////////////////////////////////////////////////

class AutoPerfDump {
public:
    AutoPerfDump() : perf_class_(0) {}

    ~AutoPerfDump() {
      for (auto hdevice : hdevices_) {
        vx_dump_perf(hdevice, stdout);
      }
    }

    void add_device(vx_device_h hdevice) {
      auto perf_class_s = getenv("PERF_CLASS");
      if (perf_class_s) {
        perf_class_ = std::atoi(perf_class_s);
        vx_dcr_write(hdevice, VX_DCR_BASE_MPM_CLASS, perf_class_);
      }
      hdevices_.push_back(hdevice);
    }

    void remove_device(vx_device_h hdevice) {
      hdevices_.remove(hdevice);
      vx_dump_perf(hdevice, stdout);
    }

    int get_perf_class() const {
      return perf_class_;
    }
    
private:
    std::list<vx_device_h> hdevices_;
    int perf_class_;
};

#ifdef DUMP_PERF_STATS
AutoPerfDump gAutoPerfDump;
#endif

void perf_add_device(vx_device_h hdevice) {
#ifdef DUMP_PERF_STATS
  gAutoPerfDump.add_device(hdevice);
#else
  (void)hdevice;
#endif
}

void perf_remove_device(vx_device_h hdevice) {
#ifdef DUMP_PERF_STATS
  gAutoPerfDump.remove_device(hdevice);
#else
  (void)hdevice;
#endif
}

///////////////////////////////////////////////////////////////////////////////

extern int vx_upload_kernel_bytes(vx_device_h hdevice, const void* content, uint64_t size) {
  int err = 0;

  if (NULL == content || 0 == size)
    return -1;

  uint64_t kernel_base_addr;
  err = vx_dev_caps(hdevice, VX_CAPS_KERNEL_BASE_ADDR, &kernel_base_addr);
  if (err != 0)
    return err;

  return vx_copy_to_dev(hdevice, kernel_base_addr, content, size);
}

extern int vx_upload_kernel_file(vx_device_h hdevice, const char* filename) {
  std::ifstream ifs(filename);
  if (!ifs) {
    std::cout << "error: " << filename << " not found" << std::endl;
    return -1;
  }

  // read file content
  ifs.seekg(0, ifs.end);
  auto size = ifs.tellg();
  auto content = new char [size];   
  ifs.seekg(0, ifs.beg);
  ifs.read(content, size);

  // upload
  int err = vx_upload_kernel_bytes(hdevice, content, size);

  // release buffer
  delete[] content;

  return err;
}

///////////////////////////////////////////////////////////////////////////////

void DeviceConfig::write(uint32_t addr, uint32_t value) {
  data_[addr] = value;
}

uint32_t DeviceConfig::read(uint32_t addr) const {
  if (0 == data_.count(addr)) {
    printf("Error: DeviceConfig::read(%d) failed\n", addr);
  }
  return data_.at(addr);
}

int dcr_initialize(vx_device_h hdevice) {
  const uint64_t startup_addr(STARTUP_ADDR);
  RT_CHECK(vx_dcr_write(hdevice, VX_DCR_BASE_STARTUP_ADDR0, startup_addr & 0xffffffff), {
    return -1;
  });

  RT_CHECK(vx_dcr_write(hdevice, VX_DCR_BASE_STARTUP_ADDR1, startup_addr >> 32), {
    return -1;
  });

  RT_CHECK(vx_dcr_write(hdevice, VX_DCR_BASE_MPM_CLASS, 0), {
    return -1;
  });
<<<<<<< HEAD
  
=======

  for (int i = 0; i < VX_DCR_RASTER_STATE_COUNT; ++i) {
    RT_CHECK(vx_dcr_write(hdevice, VX_DCR_RASTER_STATE_BEGIN + i, 0), {
      return -1;
    });
  }

  for (int i = 0; i < VX_DCR_ROP_STATE_COUNT; ++i) {
    RT_CHECK(vx_dcr_write(hdevice, VX_DCR_ROP_STATE_BEGIN + i, 0), {
      return -1;
    });
  }

  for (int i = 0; i < VX_TEX_STAGE_COUNT; ++i) {
    RT_CHECK(vx_dcr_write(hdevice, VX_DCR_TEX_STAGE, i), {
      return -1;
    });
    for (int j = 1; j < VX_DCR_TEX_STATE_COUNT; ++j) {
      RT_CHECK(vx_dcr_write(hdevice, VX_DCR_TEX_STATE_BEGIN + j, 0), {
        return -1;
      });
    }
  }
>>>>>>> 47b5f0545a5746524287aeb535791edc465b295b
  return 0;
}

///////////////////////////////////////////////////////////////////////////////

static uint64_t get_csr_64(const void* ptr, int addr) {
  auto w_ptr = reinterpret_cast<const uint32_t*>(ptr);
  uint32_t value_lo = w_ptr[addr - VX_CSR_MPM_BASE];
  uint32_t value_hi = w_ptr[addr - VX_CSR_MPM_BASE + 32];
  return (uint64_t(value_hi) << 32) | value_lo;
}

extern int vx_dump_perf(vx_device_h hdevice, FILE* stream) {
  int ret = 0;

  uint64_t instrs = 0;
  uint64_t cycles = 0;

<<<<<<< HEAD
#ifdef PERF_ENABLE

  auto calcRatio = [&](uint64_t part, uint64_t total)->int {
    if (total == 0)
      return 0;
    return int((1.0 - (double(part) / double(total))) * 100);
  };

  auto caclAvgLatency = [&](uint64_t sum, uint64_t requests)->int {
    if (requests == 0)
      return 0;
    return int(double(sum) / double(requests));
  };

  auto calcUtilization = [&](uint64_t count, uint64_t stalls)->int {
    if (count == 0)
      return 0;
    return int((double(count) / double(count + stalls)) * 100);
  };

=======
#ifdef PERF_ENABLE   
>>>>>>> 47b5f0545a5746524287aeb535791edc465b295b
  auto perf_class = gAutoPerfDump.get_perf_class();

  // PERF: pipeline stalls
  uint64_t ibuffer_stalls = 0;
  uint64_t scoreboard_stalls = 0;
  uint64_t lsu_stalls = 0;
  uint64_t fpu_stalls = 0;
  uint64_t alu_stalls = 0;
  uint64_t sfu_stalls = 0;  
  uint64_t ifetches = 0;
  uint64_t loads = 0;
  uint64_t stores = 0;
  uint64_t ifetch_lat = 0;
<<<<<<< HEAD
  uint64_t load_lat   = 0;  
=======
  uint64_t load_lat   = 0;
  // PERF: Icache 
  uint64_t icache_reads = 0;
  uint64_t icache_read_misses = 0;
  // PERF: Dcache 
  uint64_t dcache_reads = 0;
  uint64_t dcache_writes = 0;
  uint64_t dcache_read_misses = 0;
  uint64_t dcache_write_misses = 0;
  uint64_t dcache_bank_stalls = 0; 
  uint64_t dcache_mshr_stalls = 0;
  // PERF: shared memory
  uint64_t smem_reads = 0;
  uint64_t smem_writes = 0;
  uint64_t smem_bank_stalls = 0;
>>>>>>> 47b5f0545a5746524287aeb535791edc465b295b
  // PERF: l2cache 
  uint64_t l2cache_reads = 0;
  uint64_t l2cache_writes = 0;
  uint64_t l2cache_read_misses = 0;
  uint64_t l2cache_write_misses = 0;
  uint64_t l2cache_bank_stalls = 0; 
  uint64_t l2cache_mshr_stalls = 0;
  // PERF: l3cache 
  uint64_t l3cache_reads = 0;
  uint64_t l3cache_writes = 0;
  uint64_t l3cache_read_misses = 0;
  uint64_t l3cache_write_misses = 0;
  uint64_t l3cache_bank_stalls = 0; 
  uint64_t l3cache_mshr_stalls = 0;
  // PERF: memory
  uint64_t mem_reads = 0;
  uint64_t mem_writes = 0;
  uint64_t mem_lat = 0;
<<<<<<< HEAD
=======
#ifdef EXT_TEX_ENABLE
  // PERF: texunit
  uint64_t tex_mem_reads = 0;
  uint64_t tex_mem_lat = 0;
  uint64_t tex_stall_cycles = 0;
  // PERF: tex issue
  uint64_t tex_issue_stalls = 0;
  // PERF: tex tcache
  uint64_t tcache_reads = 0; 
  uint64_t tcache_read_misses = 0;
  uint64_t tcache_bank_stalls = 0; 
  uint64_t tcache_mshr_stalls = 0;
#endif
#ifdef EXT_RASTER_ENABLE
  uint64_t raster_mem_reads = 0;
  uint64_t raster_mem_lat = 0;
  uint64_t raster_stall_cycles = 0;
  // PERF: raster issue
  uint64_t raster_issue_stalls = 0;
  // PERF: raster cache
  uint64_t rcache_reads = 0;  
  uint64_t rcache_read_misses = 0;
  uint64_t rcache_bank_stalls = 0; 
  uint64_t rcache_mshr_stalls = 0;
#endif
#ifdef EXT_ROP_ENABLE
  uint64_t rop_mem_reads = 0;
  uint64_t rop_mem_writes = 0;
  uint64_t rop_mem_lat = 0;
  uint64_t rop_stall_cycles = 0;
  // PERF: rop issue
  uint64_t rop_issue_stalls = 0;
  // PERF: rop ocache
  uint64_t ocache_reads = 0;       
  uint64_t ocache_writes = 0;      
  uint64_t ocache_read_misses = 0; 
  uint64_t ocache_write_misses = 0;
  uint64_t ocache_bank_stalls = 0;   
  uint64_t ocache_mshr_stalls = 0;
#endif
>>>>>>> 47b5f0545a5746524287aeb535791edc465b295b
#endif

  uint64_t num_cores;
  ret = vx_dev_caps(hdevice, VX_CAPS_NUM_CORES, &num_cores);
  if (ret != 0)
    return ret;

<<<<<<< HEAD
#ifdef PERF_ENABLE
  uint64_t isa_flags;
  ret = vx_dev_caps(hdevice, VX_CAPS_ISA_FLAGS, &isa_flags);
  if (ret != 0)
    return ret;

  bool icache_enable  = isa_flags & VX_ISA_EXT_ICACHE;
  bool dcache_enable  = isa_flags & VX_ISA_EXT_DCACHE;
  bool l2cache_enable = isa_flags & VX_ISA_EXT_L2CACHE;
  bool l3cache_enable = isa_flags & VX_ISA_EXT_L3CACHE;
  bool smem_enable    = isa_flags & VX_ISA_EXT_SMEM;
#endif

=======
>>>>>>> 47b5f0545a5746524287aeb535791edc465b295b
  std::vector<uint8_t> staging_buf(64* sizeof(uint32_t));
      
  for (unsigned core_id = 0; core_id < num_cores; ++core_id) {    
    uint64_t mpm_mem_addr = IO_CSR_ADDR + core_id * staging_buf.size();    
    ret = vx_copy_from_dev(hdevice, staging_buf.data(), mpm_mem_addr, staging_buf.size());
    if (ret != 0)
      return ret;

<<<<<<< HEAD
=======
    uint64_t instrs_per_core = get_csr_64(staging_buf.data(), VX_CSR_MINSTRET);
    uint64_t cycles_per_core = get_csr_64(staging_buf.data(), VX_CSR_MCYCLE);
    float IPC = (float)(double(instrs_per_core) / double(cycles_per_core));
    if (num_cores > 1) fprintf(stream, "PERF: core%d: instrs=%ld, cycles=%ld, IPC=%f\n", core_id, instrs_per_core, cycles_per_core, IPC);            
    instrs += instrs_per_core;
    cycles = std::max<uint64_t>(cycles_per_core, cycles);

>>>>>>> 47b5f0545a5746524287aeb535791edc465b295b
  #ifdef PERF_ENABLE
    switch (perf_class) {
    case VX_DCR_MPM_CLASS_CORE: {
      // PERF: pipeline    
      // ibuffer_stall
      uint64_t ibuffer_stalls_per_core = get_csr_64(staging_buf.data(), VX_CSR_MPM_IBUF_ST);
      if (num_cores > 1) fprintf(stream, "PERF: core%d: ibuffer stalls=%ld\n", core_id, ibuffer_stalls_per_core);
      ibuffer_stalls += ibuffer_stalls_per_core;
      // scoreboard_stall
      uint64_t scoreboard_stalls_per_core = get_csr_64(staging_buf.data(), VX_CSR_MPM_SCRB_ST);
      if (num_cores > 1) fprintf(stream, "PERF: core%d: scoreboard stalls=%ld\n", core_id, scoreboard_stalls_per_core);
      scoreboard_stalls += scoreboard_stalls_per_core;
      // alu_stall
      uint64_t alu_stalls_per_core = get_csr_64(staging_buf.data(), VX_CSR_MPM_ALU_ST);
      if (num_cores > 1) fprintf(stream, "PERF: core%d: alu unit stalls=%ld\n", core_id, alu_stalls_per_core);
      alu_stalls += alu_stalls_per_core;      
      // lsu_stall
      uint64_t lsu_stalls_per_core = get_csr_64(staging_buf.data(), VX_CSR_MPM_LSU_ST);
      if (num_cores > 1) fprintf(stream, "PERF: core%d: lsu unit stalls=%ld\n", core_id, lsu_stalls_per_core);
      lsu_stalls += lsu_stalls_per_core;
      // fpu_stall
      uint64_t fpu_stalls_per_core = get_csr_64(staging_buf.data(), VX_CSR_MPM_FPU_ST);
      if (num_cores > 1) fprintf(stream, "PERF: core%d: fpu unit stalls=%ld\n", core_id, fpu_stalls_per_core);
      fpu_stalls += fpu_stalls_per_core;      
      // sfu_stall
      uint64_t sfu_stalls_per_core = get_csr_64(staging_buf.data(), VX_CSR_MPM_SFU_ST);
      if (num_cores > 1) fprintf(stream, "PERF: core%d: sfu unit stalls=%ld\n", core_id, sfu_stalls_per_core);
      sfu_stalls += sfu_stalls_per_core;
      // PERF: memory
      // ifetches
      uint64_t ifetches_per_core = get_csr_64(staging_buf.data(), VX_CSR_MPM_LOADS);
      if (num_cores > 1) fprintf(stream, "PERF: core%d: ifetches=%ld\n", core_id, ifetches_per_core);
      ifetches += ifetches_per_core;
      // loads
      uint64_t loads_per_core = get_csr_64(staging_buf.data(), VX_CSR_MPM_LOADS);
      if (num_cores > 1) fprintf(stream, "PERF: core%d: loads=%ld\n", core_id, loads_per_core);
      loads += loads_per_core;
      // stores
      uint64_t stores_per_core = get_csr_64(staging_buf.data(), VX_CSR_MPM_STORES);
      if (num_cores > 1) fprintf(stream, "PERF: core%d: stores=%ld\n", core_id, stores_per_core);
      stores += stores_per_core;
      // ifetch latency
      uint64_t ifetch_lat_per_core = get_csr_64(staging_buf.data(), VX_CSR_MPM_IFETCH_LAT);
      if (num_cores > 1) {
<<<<<<< HEAD
        int mem_avg_lat = caclAvgLatency(ifetch_lat_per_core, ifetches_per_core);
=======
        int mem_avg_lat = (int)(double(ifetch_lat_per_core) / double(ifetches_per_core));
>>>>>>> 47b5f0545a5746524287aeb535791edc465b295b
        fprintf(stream, "PERF: core%d: ifetch latency=%d cycles\n", core_id, mem_avg_lat);
      }
      ifetch_lat += ifetch_lat_per_core;
      // load latency
      uint64_t load_lat_per_core = get_csr_64(staging_buf.data(), VX_CSR_MPM_LOAD_LAT);
      if (num_cores > 1) {
<<<<<<< HEAD
        int mem_avg_lat = caclAvgLatency(load_lat_per_core, loads_per_core);
=======
        int mem_avg_lat = (int)(double(load_lat_per_core) / double(loads_per_core));
>>>>>>> 47b5f0545a5746524287aeb535791edc465b295b
        fprintf(stream, "PERF: core%d: load latency=%d cycles\n", core_id, mem_avg_lat);
      }
      load_lat += load_lat_per_core;      
    } break;
    case VX_DCR_MPM_CLASS_MEM: {      
<<<<<<< HEAD
      if (smem_enable) {
        // PERF: smem
        uint64_t smem_reads = get_csr_64(staging_buf.data(), VX_CSR_MPM_SMEM_READS);
        uint64_t smem_writes = get_csr_64(staging_buf.data(), VX_CSR_MPM_SMEM_WRITES);
        uint64_t smem_bank_stalls = get_csr_64(staging_buf.data(), VX_CSR_MPM_SMEM_BANK_ST);
        int smem_bank_utilization = calcUtilization(smem_reads + smem_writes, smem_bank_stalls);
        fprintf(stream, "PERF: core%d: smem reads=%ld\n", core_id, smem_reads);
        fprintf(stream, "PERF: core%d: smem writes=%ld\n", core_id, smem_writes); 
        fprintf(stream, "PERF: core%d: smem bank stalls=%ld (utilization=%d%%)\n", core_id, smem_bank_stalls, smem_bank_utilization);
      }

      if (icache_enable) {
        // PERF: Icache
        uint64_t icache_reads = get_csr_64(staging_buf.data(), VX_CSR_MPM_ICACHE_READS);
        uint64_t icache_read_misses = get_csr_64(staging_buf.data(), VX_CSR_MPM_ICACHE_MISS_R);
        int icache_read_hit_ratio = calcRatio(icache_read_misses, icache_reads);    
        fprintf(stream, "PERF: core%d: icache reads=%ld\n", core_id, icache_reads);
        fprintf(stream, "PERF: core%d: icache read misses=%ld (hit ratio=%d%%)\n", core_id, icache_read_misses, icache_read_hit_ratio);
      }
      
      if (dcache_enable) {
        // PERF: Dcache
        uint64_t dcache_reads = get_csr_64(staging_buf.data(), VX_CSR_MPM_DCACHE_READS);
        uint64_t dcache_writes = get_csr_64(staging_buf.data(), VX_CSR_MPM_DCACHE_WRITES);
        uint64_t dcache_read_misses = get_csr_64(staging_buf.data(), VX_CSR_MPM_DCACHE_MISS_R);
        uint64_t dcache_write_misses = get_csr_64(staging_buf.data(), VX_CSR_MPM_DCACHE_MISS_W);
        uint64_t dcache_bank_stalls = get_csr_64(staging_buf.data(), VX_CSR_MPM_DCACHE_BANK_ST);
        uint64_t dcache_mshr_stalls = get_csr_64(staging_buf.data(), VX_CSR_MPM_DCACHE_MSHR_ST);
        int dcache_read_hit_ratio = calcRatio(dcache_read_misses, dcache_reads);
        int dcache_write_hit_ratio = calcRatio(dcache_write_misses, dcache_writes);
        int dcache_bank_utilization = calcUtilization(dcache_reads + dcache_writes, dcache_bank_stalls);
        fprintf(stream, "PERF: core%d: dcache reads=%ld\n", core_id, dcache_reads);
        fprintf(stream, "PERF: core%d: dcache writes=%ld\n", core_id, dcache_writes);
        fprintf(stream, "PERF: core%d: dcache read misses=%ld (hit ratio=%d%%)\n", core_id, dcache_read_misses, dcache_read_hit_ratio);
        fprintf(stream, "PERF: core%d: dcache write misses=%ld (hit ratio=%d%%)\n", core_id, dcache_write_misses, dcache_write_hit_ratio);  
        fprintf(stream, "PERF: core%d: dcache bank stalls=%ld (utilization=%d%%)\n", core_id, dcache_bank_stalls, dcache_bank_utilization);
        fprintf(stream, "PERF: core%d: dcache mshr stalls=%ld\n", core_id, dcache_mshr_stalls);
      }

      if (l2cache_enable) {
        // PERF: L2cache
        l2cache_reads += get_csr_64(staging_buf.data(), VX_CSR_MPM_L2CACHE_READS);
        l2cache_writes += get_csr_64(staging_buf.data(), VX_CSR_MPM_L2CACHE_WRITES);
        l2cache_read_misses += get_csr_64(staging_buf.data(), VX_CSR_MPM_L2CACHE_MISS_R);
        l2cache_write_misses += get_csr_64(staging_buf.data(), VX_CSR_MPM_L2CACHE_MISS_W);
        l2cache_bank_stalls += get_csr_64(staging_buf.data(), VX_CSR_MPM_L2CACHE_BANK_ST);
        l2cache_mshr_stalls += get_csr_64(staging_buf.data(), VX_CSR_MPM_L2CACHE_MSHR_ST);
      }

      if (0 == core_id) {      
        if (l3cache_enable) {
          // PERF: L3cache
          l3cache_reads = get_csr_64(staging_buf.data(), VX_CSR_MPM_L3CACHE_READS);
          l3cache_writes = get_csr_64(staging_buf.data(), VX_CSR_MPM_L3CACHE_WRITES);
          l3cache_read_misses = get_csr_64(staging_buf.data(), VX_CSR_MPM_L3CACHE_MISS_R);
          l3cache_write_misses = get_csr_64(staging_buf.data(), VX_CSR_MPM_L3CACHE_MISS_W);
          l3cache_bank_stalls = get_csr_64(staging_buf.data(), VX_CSR_MPM_L3CACHE_BANK_ST);
          l3cache_mshr_stalls = get_csr_64(staging_buf.data(), VX_CSR_MPM_L3CACHE_MSHR_ST);
        }
=======
      if (0 == core_id) {
        // PERF: Icache
        icache_reads = get_csr_64(staging_buf.data(), VX_CSR_MPM_ICACHE_READS);
        icache_read_misses = get_csr_64(staging_buf.data(), VX_CSR_MPM_ICACHE_MISS_R);
      
        // PERF: Dcache
        dcache_reads = get_csr_64(staging_buf.data(), VX_CSR_MPM_DCACHE_READS);
        dcache_writes = get_csr_64(staging_buf.data(), VX_CSR_MPM_DCACHE_WRITES);
        dcache_read_misses = get_csr_64(staging_buf.data(), VX_CSR_MPM_DCACHE_MISS_R);
        dcache_write_misses = get_csr_64(staging_buf.data(), VX_CSR_MPM_DCACHE_MISS_W);
        dcache_bank_stalls = get_csr_64(staging_buf.data(), VX_CSR_MPM_DCACHE_BANK_ST);
        dcache_mshr_stalls = get_csr_64(staging_buf.data(), VX_CSR_MPM_DCACHE_MSHR_ST);
      
        // PERF: smem
        smem_reads = get_csr_64(staging_buf.data(), VX_CSR_MPM_SMEM_READS);
        smem_writes = get_csr_64(staging_buf.data(), VX_CSR_MPM_SMEM_WRITES);
        smem_bank_stalls = get_csr_64(staging_buf.data(), VX_CSR_MPM_SMEM_BANK_ST);
      
        // PERF: L2cache
        l2cache_reads = get_csr_64(staging_buf.data(), VX_CSR_MPM_L2CACHE_READS);
        l2cache_writes = get_csr_64(staging_buf.data(), VX_CSR_MPM_L2CACHE_WRITES);
        l2cache_read_misses = get_csr_64(staging_buf.data(), VX_CSR_MPM_L2CACHE_MISS_R);
        l2cache_write_misses = get_csr_64(staging_buf.data(), VX_CSR_MPM_L2CACHE_MISS_W);
        l2cache_bank_stalls = get_csr_64(staging_buf.data(), VX_CSR_MPM_L2CACHE_BANK_ST);
        l2cache_mshr_stalls = get_csr_64(staging_buf.data(), VX_CSR_MPM_L2CACHE_MSHR_ST);
      
        // PERF: L3cache
        l3cache_reads = get_csr_64(staging_buf.data(), VX_CSR_MPM_L3CACHE_READS);
        l3cache_writes = get_csr_64(staging_buf.data(), VX_CSR_MPM_L3CACHE_WRITES);
        l3cache_read_misses = get_csr_64(staging_buf.data(), VX_CSR_MPM_L3CACHE_MISS_R);
        l3cache_write_misses = get_csr_64(staging_buf.data(), VX_CSR_MPM_L3CACHE_MISS_W);
        l3cache_bank_stalls = get_csr_64(staging_buf.data(), VX_CSR_MPM_L3CACHE_BANK_ST);
        l3cache_mshr_stalls = get_csr_64(staging_buf.data(), VX_CSR_MPM_L3CACHE_MSHR_ST);
>>>>>>> 47b5f0545a5746524287aeb535791edc465b295b
      
        // PERF: memory
        mem_reads  = get_csr_64(staging_buf.data(), VX_CSR_MPM_MEM_READS);
        mem_writes = get_csr_64(staging_buf.data(), VX_CSR_MPM_MEM_WRITES);
        mem_lat    = get_csr_64(staging_buf.data(), VX_CSR_MPM_MEM_LAT);
      }
    } break;
<<<<<<< HEAD
    default:
      break;
    }
  #endif 

    uint64_t instrs_per_core = get_csr_64(staging_buf.data(), VX_CSR_MINSTRET);
    uint64_t cycles_per_core = get_csr_64(staging_buf.data(), VX_CSR_MCYCLE);
    float IPC = (float)(double(instrs_per_core) / double(cycles_per_core));
    if (num_cores > 1) fprintf(stream, "PERF: core%d: instrs=%ld, cycles=%ld, IPC=%f\n", core_id, instrs_per_core, cycles_per_core, IPC);            
    instrs += instrs_per_core;
    cycles = std::max<uint64_t>(cycles_per_core, cycles);
  }
=======
    case VX_DCR_MPM_CLASS_TEX: { 
    #ifdef EXT_TEX_ENABLE
      if (0 == core_id) {
        tex_mem_reads = get_csr_64(staging_buf.data(), VX_CSR_MPM_TEX_READS);
        tex_mem_lat   = get_csr_64(staging_buf.data(), VX_CSR_MPM_TEX_LAT);
        tex_stall_cycles = get_csr_64(staging_buf.data(), VX_CSR_MPM_TEX_STALL);
        // cache perf counters
        tcache_reads       = get_csr_64(staging_buf.data(), VX_CSR_MPM_TCACHE_READS);
        tcache_read_misses = get_csr_64(staging_buf.data(), VX_CSR_MPM_TCACHE_MISS_R);
        tcache_bank_stalls = get_csr_64(staging_buf.data(), VX_CSR_MPM_TCACHE_BANK_ST);
        tcache_mshr_stalls = get_csr_64(staging_buf.data(), VX_CSR_MPM_TCACHE_MSHR_ST);
      }
      // issue_stall
      uint64_t issue_stalls_per_core = get_csr_64(staging_buf.data(), VX_CSR_MPM_TEX_ISSUE_ST);
      if (num_cores > 1) fprintf(stream, "PERF: core%d: tex issue stalls=%ld\n", core_id, issue_stalls_per_core);
      tex_issue_stalls += issue_stalls_per_core;
    #endif
    } break;
    case VX_DCR_MPM_CLASS_RASTER: {
    #ifdef EXT_RASTER_ENABLE
      if (0 == core_id) {
        raster_mem_reads    = get_csr_64(staging_buf.data(), VX_CSR_MPM_RASTER_READS);
        raster_mem_lat      = get_csr_64(staging_buf.data(), VX_CSR_MPM_RASTER_LAT);
        raster_stall_cycles = get_csr_64(staging_buf.data(), VX_CSR_MPM_RASTER_STALL);
        // cache perf counters
        rcache_reads        = get_csr_64(staging_buf.data(), VX_CSR_MPM_RCACHE_READS);
        rcache_read_misses  = get_csr_64(staging_buf.data(), VX_CSR_MPM_RCACHE_MISS_R);
        rcache_bank_stalls  = get_csr_64(staging_buf.data(), VX_CSR_MPM_RCACHE_BANK_ST);
        rcache_mshr_stalls  = get_csr_64(staging_buf.data(), VX_CSR_MPM_RCACHE_MSHR_ST);
      }
      // issue_stall
      uint64_t raster_stalls_per_core = get_csr_64(staging_buf.data(), VX_CSR_MPM_RASTER_ISSUE_ST);
      if (num_cores > 1) fprintf(stream, "PERF: core%d: raster issue stalls=%ld\n", core_id, raster_stalls_per_core);
      raster_issue_stalls += raster_stalls_per_core;
    #endif
    } break;
    case VX_DCR_MPM_CLASS_ROP: {
    #ifdef EXT_ROP_ENABLE
      if (0 == core_id) {
        rop_mem_reads       = get_csr_64(staging_buf.data(), VX_CSR_MPM_ROP_READS);
        rop_mem_writes      = get_csr_64(staging_buf.data(), VX_CSR_MPM_ROP_WRITES);
        rop_mem_lat         = get_csr_64(staging_buf.data(), VX_CSR_MPM_ROP_LAT);
        rop_stall_cycles    = get_csr_64(staging_buf.data(), VX_CSR_MPM_ROP_STALL);
        // cache perf counters
        ocache_reads        = get_csr_64(staging_buf.data(), VX_CSR_MPM_OCACHE_READS);
        ocache_writes       = get_csr_64(staging_buf.data(), VX_CSR_MPM_OCACHE_WRITES);
        ocache_read_misses  = get_csr_64(staging_buf.data(), VX_CSR_MPM_OCACHE_MISS_R);
        ocache_write_misses = get_csr_64(staging_buf.data(), VX_CSR_MPM_OCACHE_MISS_W);
        ocache_bank_stalls  = get_csr_64(staging_buf.data(), VX_CSR_MPM_OCACHE_BANK_ST);
        ocache_mshr_stalls  = get_csr_64(staging_buf.data(), VX_CSR_MPM_OCACHE_MSHR_ST);
      }
      // issue_stall
      uint64_t rop_stalls_per_core = get_csr_64(staging_buf.data(), VX_CSR_MPM_ROP_ISSUE_ST);
      if (num_cores > 1) fprintf(stream, "PERF: core%d: rop issue stalls=%ld\n", core_id, rop_stalls_per_core);
      rop_issue_stalls += rop_stalls_per_core;
    #endif
    } break;
    default:
      break;
    }
  #endif
  }  
  
  float IPC = (float)(double(instrs) / double(cycles));
  fprintf(stream, "PERF: instrs=%ld, cycles=%ld, IPC=%f\n", instrs, cycles, IPC);    
>>>>>>> 47b5f0545a5746524287aeb535791edc465b295b
      
#ifdef PERF_ENABLE
  switch (perf_class) {
  case VX_DCR_MPM_CLASS_CORE: {    
    int ifetch_avg_lat = (int)(double(ifetch_lat) / double(ifetches));
    int load_avg_lat = (int)(double(load_lat) / double(loads));
    fprintf(stream, "PERF: ibuffer stalls=%ld\n", ibuffer_stalls);
    fprintf(stream, "PERF: scoreboard stalls=%ld\n", scoreboard_stalls);
    fprintf(stream, "PERF: alu unit stalls=%ld\n", alu_stalls);
    fprintf(stream, "PERF: lsu unit stalls=%ld\n", lsu_stalls);
    fprintf(stream, "PERF: fpu unit stalls=%ld\n", fpu_stalls);
    fprintf(stream, "PERF: sfu unit stalls=%ld\n", sfu_stalls);
    fprintf(stream, "PERF: ifetches=%ld\n", ifetches);
    fprintf(stream, "PERF: loads=%ld\n", loads);
    fprintf(stream, "PERF: stores=%ld\n", stores);    
    fprintf(stream, "PERF: ifetch latency=%d cycles\n", ifetch_avg_lat);
<<<<<<< HEAD
    fprintf(stream, "PERF: load latency=%d cycles\n", load_avg_lat);    
  } break;  
  case VX_DCR_MPM_CLASS_MEM: {    
    if (l2cache_enable) {
      l2cache_reads /= num_cores;
      l2cache_writes /= num_cores;
      l2cache_read_misses /= num_cores;
      l2cache_write_misses /= num_cores;
      l2cache_bank_stalls /= num_cores;
      l2cache_mshr_stalls /= num_cores;
      int l2cache_read_hit_ratio = calcRatio(l2cache_read_misses, l2cache_reads);
      int l2cache_write_hit_ratio = calcRatio(l2cache_write_misses, l2cache_writes);
      int l2cache_bank_utilization = calcUtilization(l2cache_reads + l2cache_writes, l2cache_bank_stalls);
          
      fprintf(stream, "PERF: l2cache reads=%ld\n", l2cache_reads);
      fprintf(stream, "PERF: l2cache writes=%ld\n", l2cache_writes);
      fprintf(stream, "PERF: l2cache read misses=%ld (hit ratio=%d%%)\n", l2cache_read_misses, l2cache_read_hit_ratio);
      fprintf(stream, "PERF: l2cache write misses=%ld (hit ratio=%d%%)\n", l2cache_write_misses, l2cache_write_hit_ratio);  
      fprintf(stream, "PERF: l2cache bank stalls=%ld (utilization=%d%%)\n", l2cache_bank_stalls, l2cache_bank_utilization);
      fprintf(stream, "PERF: l2cache mshr stalls=%ld\n", l2cache_mshr_stalls);
    }

    if (l3cache_enable) {    
      int l3cache_read_hit_ratio = calcRatio(l3cache_read_misses, l3cache_reads);
      int l3cache_write_hit_ratio = calcRatio(l3cache_write_misses, l3cache_writes);
      int l3cache_bank_utilization = calcUtilization(l3cache_reads + l3cache_writes, l3cache_bank_stalls);
      fprintf(stream, "PERF: l3cache reads=%ld\n", l3cache_reads);
      fprintf(stream, "PERF: l3cache writes=%ld\n", l3cache_writes);
      fprintf(stream, "PERF: l3cache read misses=%ld (hit ratio=%d%%)\n", l3cache_read_misses, l3cache_read_hit_ratio);
      fprintf(stream, "PERF: l3cache write misses=%ld (hit ratio=%d%%)\n", l3cache_write_misses, l3cache_write_hit_ratio);  
      fprintf(stream, "PERF: l3cache bank stalls=%ld (utilization=%d%%)\n", l3cache_bank_stalls, l3cache_bank_utilization);
      fprintf(stream, "PERF: l3cache mshr stalls=%ld\n", l3cache_mshr_stalls);
    }

    int mem_avg_lat = caclAvgLatency(mem_lat, mem_reads);   
    fprintf(stream, "PERF: memory requests=%ld (reads=%ld, writes=%ld)\n", (mem_reads + mem_writes), mem_reads, mem_writes);
    fprintf(stream, "PERF: memory latency=%d cycles\n", mem_avg_lat);
  } break;
  default:
    break;
  }
#endif 
  
  float IPC = (float)(double(instrs) / double(cycles));
  fprintf(stream, "PERF: instrs=%ld, cycles=%ld, IPC=%f\n", instrs, cycles, IPC);  
=======
    fprintf(stream, "PERF: load latency=%d cycles\n", load_avg_lat);
    
  } break;  
  case VX_DCR_MPM_CLASS_MEM: {
    int icache_read_hit_ratio = (int)((1.0 - (double(icache_read_misses) / double(icache_reads))) * 100);    
    int dcache_read_hit_ratio = (int)((1.0 - (double(dcache_read_misses) / double(dcache_reads))) * 100);
    int dcache_write_hit_ratio = (int)((1.0 - (double(dcache_write_misses) / double(dcache_writes))) * 100);
    int dcache_bank_utilization = (int)((double(dcache_reads + dcache_writes) / double(dcache_reads + dcache_writes + dcache_bank_stalls)) * 100);    
    int l2cache_read_hit_ratio = (int)((1.0 - (double(l2cache_read_misses) / double(l2cache_reads))) * 100);
    int l2cache_write_hit_ratio = (int)((1.0 - (double(l2cache_write_misses) / double(l2cache_writes))) * 100);
    int l2cache_bank_utilization = (int)((double(l2cache_reads + l2cache_writes) / double(l2cache_reads + l2cache_writes + l2cache_bank_stalls)) * 100);    
    int l3cache_read_hit_ratio = (int)((1.0 - (double(l3cache_read_misses) / double(l3cache_reads))) * 100);
    int l3cache_write_hit_ratio = (int)((1.0 - (double(l3cache_write_misses) / double(l3cache_writes))) * 100);
    int l3cache_bank_utilization = (int)((double(l3cache_reads + l3cache_writes) / double(l3cache_reads + l3cache_writes + l3cache_bank_stalls)) * 100);    
    int smem_bank_utilization = (int)((double(smem_reads + smem_writes) / double(smem_reads + smem_writes + smem_bank_stalls)) * 100);    
    int mem_avg_lat = (int)(double(mem_lat) / double(mem_reads));    
    fprintf(stream, "PERF: icache reads=%ld\n", icache_reads);
    fprintf(stream, "PERF: icache read misses=%ld (hit ratio=%d%%)\n", icache_read_misses, icache_read_hit_ratio);
    fprintf(stream, "PERF: dcache reads=%ld\n", dcache_reads);
    fprintf(stream, "PERF: dcache writes=%ld\n", dcache_writes);
    fprintf(stream, "PERF: dcache read misses=%ld (hit ratio=%d%%)\n", dcache_read_misses, dcache_read_hit_ratio);
    fprintf(stream, "PERF: dcache write misses=%ld (hit ratio=%d%%)\n", dcache_write_misses, dcache_write_hit_ratio);  
    fprintf(stream, "PERF: dcache bank stalls=%ld (utilization=%d%%)\n", dcache_bank_stalls, dcache_bank_utilization);
    fprintf(stream, "PERF: dcache mshr stalls=%ld\n", dcache_mshr_stalls);
    fprintf(stream, "PERF: smem reads=%ld\n", smem_reads);
    fprintf(stream, "PERF: smem writes=%ld\n", smem_writes); 
    fprintf(stream, "PERF: smem bank stalls=%ld (utilization=%d%%)\n", smem_bank_stalls, smem_bank_utilization);
    fprintf(stream, "PERF: l2cache reads=%ld\n", l2cache_reads);
    fprintf(stream, "PERF: l2cache writes=%ld\n", l2cache_writes);
    fprintf(stream, "PERF: l2cache read misses=%ld (hit ratio=%d%%)\n", l2cache_read_misses, l2cache_read_hit_ratio);
    fprintf(stream, "PERF: l2cache write misses=%ld (hit ratio=%d%%)\n", l2cache_write_misses, l2cache_write_hit_ratio);  
    fprintf(stream, "PERF: l2cache bank stalls=%ld (utilization=%d%%)\n", l2cache_bank_stalls, l2cache_bank_utilization);
    fprintf(stream, "PERF: l2cache mshr stalls=%ld\n", l2cache_mshr_stalls);
    fprintf(stream, "PERF: l3cache reads=%ld\n", l3cache_reads);
    fprintf(stream, "PERF: l3cache writes=%ld\n", l3cache_writes);
    fprintf(stream, "PERF: l3cache read misses=%ld (hit ratio=%d%%)\n", l3cache_read_misses, l3cache_read_hit_ratio);
    fprintf(stream, "PERF: l3cache write misses=%ld (hit ratio=%d%%)\n", l3cache_write_misses, l3cache_write_hit_ratio);  
    fprintf(stream, "PERF: l3cache bank stalls=%ld (utilization=%d%%)\n", l3cache_bank_stalls, l3cache_bank_utilization);
    fprintf(stream, "PERF: l3cache mshr stalls=%ld\n", l3cache_mshr_stalls);
    fprintf(stream, "PERF: memory requests=%ld (reads=%ld, writes=%ld)\n", (mem_reads + mem_writes), mem_reads, mem_writes);
    fprintf(stream, "PERF: memory latency=%d cycles\n", mem_avg_lat);
  } break;
  case VX_DCR_MPM_CLASS_TEX: {
  #ifdef EXT_TEX_ENABLE
    int tex_avg_lat = (int)(double(tex_mem_lat) / double(tex_mem_reads));
    int tex_stall_cycles_ratio = (int)(100 * double(tex_stall_cycles) / cycles);
    fprintf(stream, "PERF: tex memory reads=%ld\n", tex_mem_reads);
    fprintf(stream, "PERF: tex memory latency=%d cycles\n", tex_avg_lat);
    fprintf(stream, "PERF: tex stall cycles=%ld cycles (%d%%)\n", tex_stall_cycles, tex_stall_cycles_ratio);
    fprintf(stream, "PERF: tex issue stalls=%ld\n", tex_issue_stalls);
    int tcache_read_hit_ratio = (int)((1.0 - (double(tcache_read_misses) / double(tcache_reads))) * 100);
    int tcache_bank_utilization = (int)((double(tcache_reads) / double(tcache_reads + tcache_bank_stalls)) * 100);
    fprintf(stream, "PERF: tcache reads=%ld\n", tcache_reads);
    fprintf(stream, "PERF: tcache read misses=%ld (hit ratio=%d%%)\n", tcache_read_misses, tcache_read_hit_ratio);
    fprintf(stream, "PERF: tcache bank stalls=%ld (utilization=%d%%)\n", tcache_bank_stalls, tcache_bank_utilization);
    fprintf(stream, "PERF: tcache mshr stalls=%ld\n", tcache_mshr_stalls);
  #endif
  } break;
  case VX_DCR_MPM_CLASS_RASTER: {
  #ifdef EXT_RASTER_ENABLE
    int raster_mem_avg_lat = (int)(double(raster_mem_lat) / double(raster_mem_reads));
    int raster_stall_cycles_ratio = (int)(100 * double(raster_stall_cycles) / cycles);
    fprintf(stream, "PERF: raster memory reads=%ld\n", raster_mem_reads);
    fprintf(stream, "PERF: raster memory latency=%d cycles\n", raster_mem_avg_lat);
    fprintf(stream, "PERF: raster stall cycles=%ld cycles (%d%%)\n", raster_stall_cycles, raster_stall_cycles_ratio);
    fprintf(stream, "PERF: raster issue stalls=%ld\n", raster_issue_stalls);
    // cache perf counters
    int rcache_read_hit_ratio = (int)((1.0 - (double(rcache_read_misses) / double(rcache_reads))) * 100);
    int rcache_bank_utilization = (int)((double(rcache_reads) / double(rcache_reads + rcache_bank_stalls)) * 100);
    fprintf(stream, "PERF: rcache reads=%ld\n", rcache_reads);
    fprintf(stream, "PERF: rcache read misses=%ld (hit ratio=%d%%)\n", rcache_read_misses, rcache_read_hit_ratio);
    fprintf(stream, "PERF: rcache bank stalls=%ld (utilization=%d%%)\n", rcache_bank_stalls, rcache_bank_utilization);
    fprintf(stream, "PERF: rcache mshr stalls=%ld\n", rcache_mshr_stalls);
  #endif
  } break;
  case VX_DCR_MPM_CLASS_ROP: {
  #ifdef EXT_ROP_ENABLE
    int rop_mem_avg_lat = (int)(double(rop_mem_lat) / double(rop_mem_reads + rop_mem_writes));
    int rop_stall_cycles_ratio = (int)(100 * double(rop_stall_cycles) / cycles);
    fprintf(stream, "PERF: rop memory reads=%ld\n", rop_mem_reads);
    fprintf(stream, "PERF: rop memory writes=%ld\n", rop_mem_writes);
    fprintf(stream, "PERF: rop memory latency=%d cycles\n", rop_mem_avg_lat);
    fprintf(stream, "PERF: rop stall cycles=%ld cycles (%d%%)\n", rop_stall_cycles, rop_stall_cycles_ratio);
    fprintf(stream, "PERF: rop issue stalls=%ld\n", rop_issue_stalls);
    // cache perf counters
    int ocache_read_hit_ratio = (int)((1.0 - (double(ocache_read_misses) / double(ocache_reads))) * 100);
    int ocache_write_hit_ratio = (int)((1.0 - (double(ocache_write_misses) / double(ocache_writes))) * 100);
    int ocache_bank_utilization = (int)((double(ocache_reads + ocache_writes) / double(ocache_reads + ocache_writes + ocache_bank_stalls)) * 100);
    fprintf(stream, "PERF: ocache reads=%ld\n", ocache_reads);
    fprintf(stream, "PERF: ocache writes=%ld\n", ocache_writes);
    fprintf(stream, "PERF: ocache read misses=%ld (hit ratio=%d%%)\n", ocache_read_misses, ocache_read_hit_ratio);
    fprintf(stream, "PERF: ocache write misses=%ld (hit ratio=%d%%)\n", ocache_write_misses, ocache_write_hit_ratio);  
    fprintf(stream, "PERF: ocache bank stalls=%ld (utilization=%d%%)\n", ocache_bank_stalls, ocache_bank_utilization);
    fprintf(stream, "PERF: ocache mshr stalls=%ld\n", ocache_mshr_stalls);
  #endif
  } break;
  default:
    break;
  }
#endif
>>>>>>> 47b5f0545a5746524287aeb535791edc465b295b

  fflush(stream);

  return 0;
}

extern int vx_perf_counter(vx_device_h hdevice, int counter, int core_id, uint64_t* value) {
  int ret = 0;
  uint64_t num_cores;
  ret = vx_dev_caps(hdevice, VX_CAPS_NUM_CORES, &num_cores);
  if (ret != 0)
    return ret;

  if (core_id >= (int)num_cores) {
    std::cout << "error: core_id out of range" << std::endl;
    return -1;
  }

  std::vector<uint8_t> staging_buf(64 * sizeof(uint32_t));

  uint64_t _value = 0;
  
  unsigned i = 0;
  if (core_id != -1) {
    i = core_id;
    num_cores = core_id + 1;
  }
      
  for (i = 0; i < num_cores; ++i) {
    uint64_t mpm_mem_addr = IO_CSR_ADDR + i * staging_buf.size();    
    ret = vx_copy_from_dev(hdevice, staging_buf.data(), mpm_mem_addr, staging_buf.size());
    if (ret != 0)
      return ret;

    auto per_core_value = get_csr_64(staging_buf.data(), counter);     
    if (counter == VX_CSR_MCYCLE) {
      _value = std::max<uint64_t>(per_core_value, _value);
    } else {
      _value += per_core_value;
    }    
  }

  // output
  *value = _value;

  return 0;
}
