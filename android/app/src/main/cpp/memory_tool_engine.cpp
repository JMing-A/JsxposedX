#include "memory_tool_engine.h"

#include <algorithm>
#include <iterator>
#include <stdexcept>
#include <thread>
#include <unordered_set>
#include <utility>

#include "memory_tool_reader.h"
#include "memory_tool_regions.h"
#include "memory_tool_value.h"

namespace memory_tool {

namespace {

uint64_t ElapsedMilliseconds(const std::chrono::steady_clock::time_point& started_at) {
    if (started_at == std::chrono::steady_clock::time_point{}) {
        return 0;
    }
    return static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::milliseconds>(
                                     std::chrono::steady_clock::now() - started_at)
                                     .count());
}

const MemoryRegion* FindRegionByStart(const std::vector<MemoryRegion>& regions,
                                      uint64_t region_start) {
    const auto iterator = std::lower_bound(
        regions.begin(),
        regions.end(),
        region_start,
        [](const MemoryRegion& region, uint64_t start_address) {
            return region.start_address < start_address;
        });
    if (iterator == regions.end()) {
        return nullptr;
    }
    if (iterator->start_address != region_start) {
        return nullptr;
    }
    return &(*iterator);
}

std::vector<MemoryRegion> FilterRegionsByTypeKeys(const std::vector<MemoryRegion>& regions,
                                                  const std::vector<std::string>& allowed_keys) {
    if (allowed_keys.empty()) {
        return regions;
    }

    const std::unordered_set<std::string> allowed_key_set(
        allowed_keys.begin(),
        allowed_keys.end());
    std::vector<MemoryRegion> filtered;
    filtered.reserve(regions.size());
    for (const MemoryRegion& region : regions) {
        const std::string region_key = ClassifyMemoryRegion(region);
        if (allowed_key_set.find(region_key) != allowed_key_set.end()) {
            filtered.push_back(region);
        }
    }
    return filtered;
}

size_t ResolveFirstScanWorkerCount(size_t region_count) {
    if (region_count <= 1) {
        return region_count;
    }

    const unsigned int hardware_workers = std::thread::hardware_concurrency();
    const size_t preferred_workers = hardware_workers == 0 ? 4U : hardware_workers;
    return std::max<size_t>(1, std::min(region_count, preferred_workers));
}

std::vector<std::vector<MemoryRegion>> PartitionRegionsForWorkers(
    const std::vector<MemoryRegion>& regions,
    size_t worker_count) {
    if (worker_count <= 1) {
        return {regions};
    }

    std::vector<std::vector<MemoryRegion>> buckets(worker_count);
    uint64_t total_bytes = 0;
    for (const MemoryRegion& region : regions) {
        total_bytes += region.size;
    }
    const uint64_t target_bucket_bytes =
        std::max<uint64_t>(1, total_bytes / worker_count);

    size_t bucket_index = 0;
    uint64_t current_bucket_bytes = 0;
    for (size_t region_index = 0; region_index < regions.size(); ++region_index) {
        const MemoryRegion& region = regions[region_index];
        buckets[bucket_index].push_back(region);
        current_bucket_bytes += region.size;

        const size_t remaining_regions = regions.size() - region_index - 1;
        const bool canAdvance = bucket_index + 1 < worker_count;
        const bool shouldAdvance =
            canAdvance &&
            current_bucket_bytes >= target_bucket_bytes &&
            remaining_regions >= (worker_count - bucket_index - 1);
        if (shouldAdvance) {
            ++bucket_index;
            current_bucket_bytes = 0;
        }
    }
    return buckets;
}

SearchRuntimeMode ToRuntimeMode(SpecialSearchMode mode) {
    switch (mode) {
        case SpecialSearchMode::kXor:
            return SearchRuntimeMode::kXor;
        case SpecialSearchMode::kAuto:
            return SearchRuntimeMode::kAuto;
        case SpecialSearchMode::kNone:
            return SearchRuntimeMode::kStandard;
    }
    return SearchRuntimeMode::kStandard;
}

SearchValueType ResolveSessionType(const SearchValue& value, SpecialSearchMode mode) {
    switch (mode) {
        case SpecialSearchMode::kXor:
            return SearchValueType::kI32;
        case SpecialSearchMode::kAuto:
            return SearchValueType::kBytes;
        case SpecialSearchMode::kNone:
            return value.type;
    }
    return value.type;
}

bool CanContinueWithRequestMode(SearchRuntimeMode session_mode,
                                SearchRuntimeMode request_mode) {
    if (session_mode == request_mode) {
        return true;
    }
    return session_mode == SearchRuntimeMode::kAuto &&
           request_mode == SearchRuntimeMode::kStandard;
}

std::vector<SearchResultEntry> FilterResultsByMatchedType(
    const std::vector<SearchResultEntry>& results,
    SearchValueType type) {
    std::vector<SearchResultEntry> filtered;
    filtered.reserve(results.size());
    for (const SearchResultEntry& entry : results) {
        if (entry.matched_type != type) {
            continue;
        }
        filtered.push_back(entry);
    }
    return filtered;
}

bool BuildWritableValuePayload(const SearchValue& value,
                               std::vector<uint8_t>* bytes,
                               BytesDisplayEncoding* bytes_display_encoding,
                               std::string* display_value,
                               std::string* error) {
    if (bytes == nullptr || bytes_display_encoding == nullptr || display_value == nullptr) {
        if (error != nullptr) {
            *error = "Invalid writable value payload.";
        }
        return false;
    }

    if (!BuildSearchPattern(value, bytes, error)) {
        return false;
    }

    *bytes_display_encoding = ResolveBytesDisplayEncoding(value);
    *display_value = FormatDisplayValue(value.type,
                                        *bytes,
                                        value.little_endian,
                                        *bytes_display_encoding);
    return true;
}

}  // namespace

MemoryToolEngine& MemoryToolEngine::Instance() {
    static MemoryToolEngine instance;
    return instance;
}

std::vector<MemoryRegion> MemoryToolEngine::GetMemoryRegions(int pid,
                                                             int offset,
                                                             int limit,
                                                             bool readable_only,
                                                             bool include_anonymous,
                                                             bool include_file_backed) {
    const std::vector<MemoryRegion> all_regions =
        ReadProcessRegions(pid, readable_only, include_anonymous, include_file_backed);
    if (limit <= 0 || offset >= static_cast<int>(all_regions.size())) {
        return {};
    }

    const size_t start = static_cast<size_t>(std::max(offset, 0));
    const size_t end = std::min(all_regions.size(), start + static_cast<size_t>(limit));
    return std::vector<MemoryRegion>(all_regions.begin() + static_cast<std::ptrdiff_t>(start),
                                     all_regions.begin() + static_cast<std::ptrdiff_t>(end));
}

SearchSessionStateView MemoryToolEngine::GetSearchSessionState() {
    std::lock_guard<std::mutex> lock(mutex_);
    return BuildSessionStateLocked();
}

SearchTaskStateView MemoryToolEngine::GetSearchTaskState() {
    std::lock_guard<std::mutex> lock(mutex_);
    return BuildTaskStateLocked();
}

std::vector<SearchResultView> MemoryToolEngine::GetSearchResults(int offset, int limit) {
    std::lock_guard<std::mutex> lock(mutex_);
    EnsureActiveSessionLocked();
    if (limit <= 0 || offset >= static_cast<int>(session_.results.size())) {
        return {};
    }

    const size_t start = static_cast<size_t>(std::max(offset, 0));
    const size_t end = std::min(session_.results.size(), start + static_cast<size_t>(limit));
    std::vector<SearchResultView> views;
    views.reserve(end - start);
    for (size_t index = start; index < end; ++index) {
        views.push_back(BuildSearchResultViewLocked(session_.results[index]));
    }
    return views;
}

std::vector<MemoryValuePreview> MemoryToolEngine::ReadMemoryValues(
    const std::vector<MemoryReadRequest>& requests) {
    std::lock_guard<std::mutex> lock(mutex_);
    EnsureActiveSessionLocked();
    if (!IsProcessAlive(session_.pid)) {
        session_.Clear();
        throw std::runtime_error("Search session target process is no longer available.");
    }

    ProcessMemoryReader reader(session_.pid);
    std::vector<MemoryValuePreview> previews;
    previews.reserve(requests.size());
    for (const MemoryReadRequest& request : requests) {
        const size_t length = ResolveValueByteLength(request.type, request.length);
        if (length == 0) {
            continue;
        }

        std::vector<uint8_t> buffer;
        if (!reader.Read(request.address, length, &buffer)) {
            continue;
        }

        MemoryValuePreview preview;
        preview.address = request.address;
        preview.type = request.type;
        preview.raw_bytes = buffer;
        preview.display_value = FormatDisplayValue(request.type,
                                                   buffer,
                                                   session_.little_endian,
                                                   request.type == SearchValueType::kBytes
                                                       ? session_.bytes_display_encoding
                                                       : BytesDisplayEncoding::kHex);
        previews.push_back(std::move(preview));
    }
    return previews;
}

void MemoryToolEngine::WriteMemoryValue(const MemoryWriteRequest& request) {
    std::vector<uint8_t> value_bytes;
    BytesDisplayEncoding bytes_display_encoding = BytesDisplayEncoding::kHex;
    std::string display_value;
    std::string error;
    if (!BuildWritableValuePayload(request.value,
                                   &value_bytes,
                                   &bytes_display_encoding,
                                   &display_value,
                                   &error)) {
        throw std::runtime_error(error.empty() ? "Invalid writable value." : error);
    }

    int pid = 0;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        EnsureActiveSessionLocked();
        if (!IsProcessAlive(session_.pid)) {
            session_.Clear();
            throw std::runtime_error("Search session target process is no longer available.");
        }
        pid = session_.pid;
    }

    ProcessMemoryReader reader(pid);
    if (!reader.Write(request.address, value_bytes)) {
        throw std::runtime_error("Failed to write memory value.");
    }
}

void MemoryToolEngine::SetMemoryFreeze(const MemoryFreezeRequest& request) {
    std::vector<uint8_t> value_bytes;
    BytesDisplayEncoding bytes_display_encoding = BytesDisplayEncoding::kHex;
    std::string display_value;
    std::string error;
    if (request.enabled &&
        !BuildWritableValuePayload(request.value,
                                   &value_bytes,
                                   &bytes_display_encoding,
                                   &display_value,
                                   &error)) {
        throw std::runtime_error(error.empty() ? "Invalid frozen value." : error);
    }

    std::lock_guard<std::mutex> lock(mutex_);
    EnsureActiveSessionLocked();
    if (!IsProcessAlive(session_.pid)) {
        session_.Clear();
        throw std::runtime_error("Search session target process is no longer available.");
    }

    auto entry_iterator = std::find_if(
        frozen_entries_.begin(),
        frozen_entries_.end(),
        [&request](const FrozenWriteEntry& entry) {
            return entry.address == request.address;
        });

    if (!request.enabled) {
        if (entry_iterator != frozen_entries_.end()) {
            frozen_entries_.erase(entry_iterator);
        }
        NotifyFreezeWorkerLocked();
        return;
    }

    FrozenWriteEntry next_entry;
    next_entry.pid = session_.pid;
    next_entry.address = request.address;
    next_entry.type = request.value.type;
    next_entry.value_bytes = std::move(value_bytes);
    next_entry.little_endian = request.value.little_endian;
    next_entry.bytes_display_encoding = bytes_display_encoding;

    if (entry_iterator == frozen_entries_.end()) {
        frozen_entries_.push_back(std::move(next_entry));
    } else {
        *entry_iterator = std::move(next_entry);
    }

    EnsureFreezeWorkerLocked();
    NotifyFreezeWorkerLocked();
}

std::vector<FrozenMemoryValueView> MemoryToolEngine::GetFrozenMemoryValues() {
    std::lock_guard<std::mutex> lock(mutex_);
    frozen_entries_.erase(
        std::remove_if(
            frozen_entries_.begin(),
            frozen_entries_.end(),
            [](const FrozenWriteEntry& entry) { return !IsProcessAlive(entry.pid); }),
        frozen_entries_.end());

    std::vector<FrozenMemoryValueView> values;
    values.reserve(frozen_entries_.size());
    for (const FrozenWriteEntry& entry : frozen_entries_) {
        FrozenMemoryValueView value;
        value.pid = entry.pid;
        value.address = entry.address;
        value.type = entry.type;
        value.raw_bytes = entry.value_bytes;
        value.display_value = FormatDisplayValue(entry.type,
                                                 entry.value_bytes,
                                                 entry.little_endian,
                                                 entry.bytes_display_encoding);
        values.push_back(std::move(value));
    }
    return values;
}

void MemoryToolEngine::FirstScan(int pid,
                                 const SearchValue& value,
                                 SearchMatchMode match_mode,
                                 const std::vector<std::string>& range_section_keys,
                                 bool scan_all_readable_regions) {
    if (match_mode != SearchMatchMode::kExact) {
        throw std::runtime_error("Only exact scan is supported.");
    }

    std::vector<uint8_t> pattern;
    std::vector<SearchPatternVariant> auto_variants;
    uint32_t xor_target_value = 0;
    std::string error;
    std::string current_display_value;
    const SpecialSearchMode special_mode = ResolveSpecialSearchMode(value);
    switch (special_mode) {
        case SpecialSearchMode::kXor:
            if (!ParseXorTargetValue(value, &xor_target_value, &current_display_value, &error)) {
                throw std::runtime_error(error.empty() ? "Invalid XOR search value." : error);
            }
            break;
        case SpecialSearchMode::kAuto: {
            AutoSearchPlan auto_plan;
            if (!BuildAutoSearchPlan(value, &auto_plan, &error)) {
                throw std::runtime_error(error.empty() ? "Invalid AUTO search value." : error);
            }
            auto_variants = std::move(auto_plan.variants);
            current_display_value = std::move(auto_plan.display_value);
            break;
        }
        case SpecialSearchMode::kNone:
            if (!BuildSearchPattern(value, &pattern, &error)) {
                throw std::runtime_error(error.empty() ? "Invalid search value." : error);
            }
            current_display_value = FormatDisplayValue(value.type,
                                                       pattern,
                                                       value.little_endian,
                                                       ResolveBytesDisplayEncoding(value));
            break;
    }

    const SearchRuntimeMode runtime_mode = ToRuntimeMode(special_mode);
    const SearchValueType session_type = ResolveSessionType(value, special_mode);
    const bool little_endian = value.little_endian;
    const BytesDisplayEncoding bytes_display_encoding =
        ResolveBytesDisplayEncoding(value);
    const size_t session_value_size = runtime_mode == SearchRuntimeMode::kXor
                                          ? sizeof(uint32_t)
                                          : runtime_mode == SearchRuntimeMode::kAuto
                                              ? 0
                                              : pattern.size();
    std::vector<uint8_t> current_value_bytes;
    if (runtime_mode == SearchRuntimeMode::kStandard) {
        current_value_bytes = pattern;
    }
    const uint64_t generation = [this, pid]() {
        std::lock_guard<std::mutex> lock(mutex_);
        session_.Clear();
        return StartTaskLocked(true, pid);
    }();

    std::thread([this,
                 generation,
                 pid,
                 pattern = std::move(pattern),
                 auto_variants = std::move(auto_variants),
                 xor_target_value,
                 runtime_mode,
                 session_type,
                 little_endian,
                 bytes_display_encoding,
                 session_value_size,
                 current_display_value = std::move(current_display_value),
                 current_value_bytes = std::move(current_value_bytes),
                 range_section_keys,
                 scan_all_readable_regions]() {
        try {
            if (!IsProcessAlive(pid)) {
                throw std::runtime_error("Target process is no longer available.");
            }

            std::vector<MemoryRegion> regions = ReadProcessRegions(pid, true, true, true);
            if (!scan_all_readable_regions) {
                regions = FilterRegionsByTypeKeys(regions, range_section_keys);
            }
            uint64_t total_byte_count = 0;
            for (const MemoryRegion& region : regions) {
                total_byte_count += region.size;
            }
            const size_t worker_count = ResolveFirstScanWorkerCount(regions.size());
            const std::vector<std::vector<MemoryRegion>> region_buckets =
                PartitionRegionsForWorkers(regions, worker_count);

            std::atomic_size_t processed_region_count{0};
            std::atomic_uint64_t processed_byte_count{0};
            std::atomic_size_t aggregated_result_count{0};
            std::atomic_bool should_stop{false};
            std::mutex progress_mutex;
            std::vector<std::vector<SearchResultEntry>> worker_results(region_buckets.size());
            std::vector<std::thread> workers;
            workers.reserve(region_buckets.size());

            const auto report_progress = [this,
                                          generation,
                                          &regions,
                                          &processed_region_count,
                                          &processed_byte_count,
                                          &aggregated_result_count,
                                          &should_stop,
                                          &progress_mutex,
                                          total_byte_count]() {
                std::lock_guard<std::mutex> lock(progress_mutex);
                if (should_stop.load()) {
                    return false;
                }

                SearchScanProgress progress;
                progress.total_region_count = regions.size();
                progress.total_byte_count = total_byte_count;
                progress.processed_region_count = processed_region_count.load();
                progress.processed_byte_count = processed_byte_count.load();
                progress.result_count = aggregated_result_count.load();

                if (!UpdateTaskProgress(generation, progress)) {
                    should_stop.store(true);
                    return false;
                }
                return true;
            };

            for (size_t index = 0; index < region_buckets.size(); ++index) {
                if (region_buckets[index].empty()) {
                    continue;
                }

                workers.emplace_back([&pattern,
                                      &auto_variants,
                                      &region_buckets,
                                      &worker_results,
                                      &processed_region_count,
                                      &processed_byte_count,
                                      &aggregated_result_count,
                                      &report_progress,
                                      &should_stop,
                                      index,
                                      pid,
                                      xor_target_value,
                                      runtime_mode,
                                      little_endian,
                                      session_type]() {
                    ProcessMemoryReader reader(pid);
                    SearchScanProgress local_progress;
                    const auto on_progress = [&](const SearchScanProgress& progress) {
                        if (should_stop.load()) {
                            return false;
                        }

                        processed_region_count.fetch_add(progress.processed_region_count -
                                                         local_progress.processed_region_count);
                        processed_byte_count.fetch_add(progress.processed_byte_count -
                                                       local_progress.processed_byte_count);
                        aggregated_result_count.fetch_add(progress.result_count -
                                                          local_progress.result_count);
                        local_progress = progress;
                        return report_progress();
                    };

                    switch (runtime_mode) {
                        case SearchRuntimeMode::kXor:
                            worker_results[index] = ::memory_tool::FirstScanXor(
                                &reader,
                                region_buckets[index],
                                xor_target_value,
                                little_endian,
                                on_progress);
                            return;
                        case SearchRuntimeMode::kAuto:
                            worker_results[index] = ::memory_tool::FirstScanMultiType(
                                &reader,
                                region_buckets[index],
                                auto_variants,
                                on_progress);
                            return;
                        case SearchRuntimeMode::kStandard:
                            worker_results[index] = ::memory_tool::FirstScan(
                                &reader,
                                region_buckets[index],
                                pattern,
                                session_type,
                                on_progress);
                            return;
                    }
                });
            }

            for (std::thread& worker : workers) {
                if (worker.joinable()) {
                    worker.join();
                }
            }

            if (should_stop.load()) {
                return;
            }

            std::vector<SearchResultEntry> results;
            size_t result_count = 0;
            for (const auto& entries : worker_results) {
                result_count += entries.size();
            }
            results.reserve(result_count);
            for (auto& entries : worker_results) {
                results.insert(results.end(),
                               std::make_move_iterator(entries.begin()),
                               std::make_move_iterator(entries.end()));
            }
            SearchSession next_session;
            next_session.has_active_session = true;
            next_session.pid = pid;
            next_session.type = session_type;
            next_session.mode = runtime_mode;
            next_session.exact_mode = true;
            next_session.little_endian = little_endian;
            next_session.bytes_display_encoding = bytes_display_encoding;
            next_session.value_size = session_value_size;
            next_session.current_value_bytes = current_value_bytes;
            next_session.current_display_value = current_display_value;
            next_session.regions = std::move(regions);
            next_session.results = std::move(results);
            FinishTaskSuccess(generation, std::move(next_session), result_count);
        } catch (const std::exception& exception) {
            FinishTaskFailure(generation, exception.what());
        } catch (...) {
            FinishTaskFailure(generation, "Unexpected native scan failure.");
        }
    }).detach();
}

void MemoryToolEngine::NextScan(const SearchValue& value, SearchMatchMode match_mode) {
    if (match_mode != SearchMatchMode::kExact) {
        throw std::runtime_error("Only exact scan is supported.");
    }

    std::vector<uint8_t> pattern;
    std::vector<SearchPatternVariant> auto_variants;
    uint32_t xor_target_value = 0;
    std::string error;
    std::string current_display_value;
    const SpecialSearchMode special_mode = ResolveSpecialSearchMode(value);
    switch (special_mode) {
        case SpecialSearchMode::kXor:
            if (!ParseXorTargetValue(value, &xor_target_value, &current_display_value, &error)) {
                throw std::runtime_error(error.empty() ? "Invalid XOR search value." : error);
            }
            break;
        case SpecialSearchMode::kAuto: {
            AutoSearchPlan auto_plan;
            if (!BuildAutoSearchPlan(value, &auto_plan, &error)) {
                throw std::runtime_error(error.empty() ? "Invalid AUTO search value." : error);
            }
            auto_variants = std::move(auto_plan.variants);
            current_display_value = std::move(auto_plan.display_value);
            break;
        }
        case SpecialSearchMode::kNone:
            if (!BuildSearchPattern(value, &pattern, &error)) {
                throw std::runtime_error(error.empty() ? "Invalid search value." : error);
            }
            current_display_value = FormatDisplayValue(value.type,
                                                       pattern,
                                                       value.little_endian,
                                                       ResolveBytesDisplayEncoding(value));
            break;
    }

    SearchSession session_snapshot;
    const SearchRuntimeMode runtime_mode = ToRuntimeMode(special_mode);
    const SearchValueType session_type = ResolveSessionType(value, special_mode);
    const uint64_t generation = [this, &session_snapshot, &value]() {
        std::lock_guard<std::mutex> lock(mutex_);
        EnsureTaskNotRunningLocked();
        EnsureActiveSessionLocked();
        if (!IsProcessAlive(session_.pid)) {
            session_.Clear();
            throw std::runtime_error("Search session target process is no longer available.");
        }
        const SearchRuntimeMode request_mode = ToRuntimeMode(ResolveSpecialSearchMode(value));
        if (!CanContinueWithRequestMode(session_.mode, request_mode)) {
            throw std::runtime_error("Search value type does not match the active session.");
        }
        if (session_.mode == SearchRuntimeMode::kStandard &&
            request_mode == SearchRuntimeMode::kStandard &&
            value.type != session_.type) {
            throw std::runtime_error("Search value type does not match the active session.");
        }
        session_snapshot = session_;
        return StartTaskLocked(false, session_.pid);
    }();

    const bool little_endian = value.little_endian;
    const BytesDisplayEncoding bytes_display_encoding =
        ResolveBytesDisplayEncoding(value);
    const size_t session_value_size = runtime_mode == SearchRuntimeMode::kXor
                                          ? sizeof(uint32_t)
                                          : runtime_mode == SearchRuntimeMode::kAuto
                                              ? 0
                                              : pattern.size();
    std::vector<uint8_t> current_value_bytes;
    if (runtime_mode == SearchRuntimeMode::kStandard) {
        current_value_bytes = pattern;
    }

    std::thread([this,
                 generation,
                 session_snapshot = std::move(session_snapshot),
                 pattern = std::move(pattern),
                 auto_variants = std::move(auto_variants),
                 xor_target_value,
                 runtime_mode,
                 session_type,
                 little_endian,
                 bytes_display_encoding,
                 session_value_size,
                 current_display_value = std::move(current_display_value),
                 current_value_bytes = std::move(current_value_bytes)]() mutable {
        try {
            ProcessMemoryReader reader(session_snapshot.pid);
            const bool isAutoSessionToTypedScan =
                session_snapshot.mode == SearchRuntimeMode::kAuto &&
                runtime_mode == SearchRuntimeMode::kStandard;
            const std::vector<SearchResultEntry> next_scan_source_results =
                isAutoSessionToTypedScan
                    ? FilterResultsByMatchedType(session_snapshot.results, session_type)
                    : session_snapshot.results;

            std::vector<SearchResultEntry> results;
            switch (runtime_mode) {
                case SearchRuntimeMode::kXor:
                    results = ::memory_tool::NextScanXor(
                        &reader,
                        next_scan_source_results,
                        xor_target_value,
                        little_endian,
                        [this, generation](const SearchScanProgress& progress) {
                            return UpdateTaskProgress(generation, progress);
                        });
                    break;
                case SearchRuntimeMode::kAuto:
                    results = ::memory_tool::NextScanMultiType(
                        &reader,
                        next_scan_source_results,
                        auto_variants,
                        [this, generation](const SearchScanProgress& progress) {
                            return UpdateTaskProgress(generation, progress);
                        });
                    break;
                case SearchRuntimeMode::kStandard:
                    results = ::memory_tool::NextScan(
                        &reader,
                        next_scan_source_results,
                        pattern,
                        [this, generation](const SearchScanProgress& progress) {
                            return UpdateTaskProgress(generation, progress);
                        });
                    break;
            }

            const size_t result_count = results.size();
            session_snapshot.results = std::move(results);
            session_snapshot.type = session_type;
            session_snapshot.mode = runtime_mode;
            session_snapshot.value_size = session_value_size;
            session_snapshot.little_endian = little_endian;
            session_snapshot.bytes_display_encoding = bytes_display_encoding;
            session_snapshot.current_value_bytes = current_value_bytes;
            session_snapshot.current_display_value = current_display_value;
            FinishTaskSuccess(generation, std::move(session_snapshot), result_count);
        } catch (const std::exception& exception) {
            FinishTaskFailure(generation, exception.what());
        } catch (...) {
            FinishTaskFailure(generation, "Unexpected native scan failure.");
        }
    }).detach();
}

void MemoryToolEngine::CancelSearch() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (task_.view.status != SearchTaskStatus::kRunning) {
        return;
    }

    if (task_.cancel_flag) {
        task_.cancel_flag->store(true);
    }
    task_.view.status = SearchTaskStatus::kCancelled;
    task_.view.can_cancel = false;
    task_.view.elapsed_milliseconds = ElapsedMilliseconds(task_.started_at);
    task_.view.message = "Search cancelled.";
}

void MemoryToolEngine::ResetSearchSession() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (task_.cancel_flag) {
        task_.cancel_flag->store(true);
    }
    ++task_generation_counter_;
    task_ = SearchTaskRuntime{};
    session_.Clear();
}

void MemoryToolEngine::EnsureFreezeWorkerLocked() {
    if (freeze_worker_started_) {
        return;
    }

    freeze_worker_started_ = true;
    std::thread([this]() { FreezeWorkerLoop(); }).detach();
}

void MemoryToolEngine::NotifyFreezeWorkerLocked() {
    freeze_condition_.notify_one();
}

void MemoryToolEngine::FreezeWorkerLoop() {
    while (true) {
        std::vector<FrozenWriteEntry> snapshot;
        {
            std::unique_lock<std::mutex> lock(mutex_);
            if (frozen_entries_.empty()) {
                freeze_condition_.wait(lock, [this]() { return !frozen_entries_.empty(); });
            } else {
                freeze_condition_.wait_for(lock, std::chrono::milliseconds(120));
            }
            snapshot = frozen_entries_;
        }

        if (snapshot.empty()) {
            continue;
        }

        std::vector<uint64_t> inactive_addresses;
        for (const FrozenWriteEntry& entry : snapshot) {
            if (!IsProcessAlive(entry.pid)) {
                inactive_addresses.push_back(entry.address);
                continue;
            }

            ProcessMemoryReader reader(entry.pid);
            if (!reader.Write(entry.address, entry.value_bytes) &&
                !IsProcessAlive(entry.pid)) {
                inactive_addresses.push_back(entry.address);
            }
        }

        if (inactive_addresses.empty()) {
            continue;
        }

        std::lock_guard<std::mutex> lock(mutex_);
        frozen_entries_.erase(
            std::remove_if(
                frozen_entries_.begin(),
                frozen_entries_.end(),
                [&inactive_addresses](const FrozenWriteEntry& entry) {
                    return std::find(inactive_addresses.begin(),
                                     inactive_addresses.end(),
                                     entry.address) != inactive_addresses.end();
                }),
            frozen_entries_.end());
    }
}

SearchSessionStateView MemoryToolEngine::BuildSessionStateLocked() const {
    SearchSessionStateView state;
    state.has_active_session = session_.has_active_session;
    state.pid = session_.pid;
    state.type = session_.type;
    state.region_count = session_.regions.size();
    state.result_count = session_.results.size();
    state.exact_mode = session_.exact_mode;
    state.little_endian = session_.little_endian;
    return state;
}

SearchTaskStateView MemoryToolEngine::BuildTaskStateLocked() const {
    SearchTaskStateView state = task_.view;
    if (state.status == SearchTaskStatus::kRunning || state.status == SearchTaskStatus::kCancelled) {
        state.elapsed_milliseconds = ElapsedMilliseconds(task_.started_at);
    }
    return state;
}

SearchResultView MemoryToolEngine::BuildSearchResultViewLocked(const SearchResultEntry& entry) const {
    SearchResultView view;
    view.address = entry.address;
    view.region_start = entry.region_start;
    if (const MemoryRegion* region = FindRegionByStart(session_.regions, entry.region_start);
        region != nullptr) {
        view.region_type_key = ClassifyMemoryRegion(*region);
    } else {
        view.region_type_key = "other";
    }
    view.type = entry.matched_type;
    const size_t byte_length = view.type == SearchValueType::kBytes
                                   ? session_.value_size
                                   : ResolveValueByteLength(view.type, session_.value_size);
    view.raw_bytes.assign(byte_length, 0);
    view.display_value = session_.current_display_value;
    return view;
}

void MemoryToolEngine::EnsureActiveSessionLocked() const {
    if (!session_.has_active_session) {
        throw std::runtime_error("No active search session.");
    }
}

void MemoryToolEngine::EnsureTaskNotRunningLocked() const {
    if (task_.view.status == SearchTaskStatus::kRunning) {
        throw std::runtime_error("A search task is already running.");
    }
}

uint64_t MemoryToolEngine::StartTaskLocked(bool is_first_scan, int pid) {
    EnsureTaskNotRunningLocked();

    if (task_.cancel_flag) {
        task_.cancel_flag->store(true);
    }

    ++task_generation_counter_;
    task_ = SearchTaskRuntime{};
    task_.generation = task_generation_counter_;
    task_.started_at = std::chrono::steady_clock::now();
    task_.cancel_flag = std::make_shared<std::atomic_bool>(false);
    task_.view.status = SearchTaskStatus::kRunning;
    task_.view.is_first_scan = is_first_scan;
    task_.view.pid = pid;
    task_.view.can_cancel = true;
    task_.view.message = is_first_scan ? "First scan is running." : "Next scan is running.";
    return task_.generation;
}

bool MemoryToolEngine::UpdateTaskProgress(uint64_t generation, const SearchScanProgress& progress) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (task_.generation != generation || task_.view.status != SearchTaskStatus::kRunning) {
        return false;
    }
    if (task_.cancel_flag && task_.cancel_flag->load()) {
        return false;
    }

    task_.view.processed_region_count = progress.processed_region_count;
    task_.view.total_region_count = progress.total_region_count;
    task_.view.processed_entry_count = progress.processed_entry_count;
    task_.view.total_entry_count = progress.total_entry_count;
    task_.view.processed_byte_count = progress.processed_byte_count;
    task_.view.total_byte_count = progress.total_byte_count;
    task_.view.result_count = progress.result_count;
    task_.view.elapsed_milliseconds = ElapsedMilliseconds(task_.started_at);
    return true;
}

void MemoryToolEngine::FinishTaskSuccess(uint64_t generation,
                                         SearchSession&& next_session,
                                         size_t result_count) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (task_.generation != generation || task_.view.status != SearchTaskStatus::kRunning) {
        return;
    }
    if (task_.cancel_flag && task_.cancel_flag->load()) {
        return;
    }

    session_ = std::move(next_session);
    task_.view.status = SearchTaskStatus::kCompleted;
    task_.view.can_cancel = false;
    task_.view.result_count = result_count;
    task_.view.processed_region_count = task_.view.total_region_count;
    task_.view.processed_entry_count = task_.view.total_entry_count;
    task_.view.processed_byte_count = task_.view.total_byte_count;
    task_.view.elapsed_milliseconds = ElapsedMilliseconds(task_.started_at);
    task_.view.message = "Search completed.";
}

void MemoryToolEngine::FinishTaskFailure(uint64_t generation, const std::string& message) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (task_.generation != generation || task_.view.status != SearchTaskStatus::kRunning) {
        return;
    }

    task_.view.status = SearchTaskStatus::kFailed;
    task_.view.can_cancel = false;
    task_.view.elapsed_milliseconds = ElapsedMilliseconds(task_.started_at);
    task_.view.message = message;
}

}  // namespace memory_tool
