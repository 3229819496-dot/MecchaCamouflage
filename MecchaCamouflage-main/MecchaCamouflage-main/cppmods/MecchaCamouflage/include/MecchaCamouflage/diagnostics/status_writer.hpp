#pragma once

#include <cstdint>
#include <string>

namespace MecchaCamouflage::Diagnostics
{
    struct LastStatusSnapshot
    {
        const char* phase{"unknown"};
        bool target_resolve_ok{false};
        std::uint64_t play_id{0};
        int success{0};
        int failures{0};
        bool visible_backend{false};
        int body_hits{0};
        int uv_hits{0};
        int side_enabled{0};
        int side_query_attempts{0};
        int side_query_success{0};
        int side_query_uv_hits{0};
        int side_projected_pixels{0};
        int side_material_hits{0};
        int side_seeds{0};
        int side_nearest_sources{0};
        int side_duplicate_texels{0};
        int side_normal_suspect{0};
        std::string paint_backend{};
        std::string side_backend{};
        std::string last_failure{};
        std::string world{};
        std::string pawn{};
        std::string component{};
    };

    void write_last_status_file(const LastStatusSnapshot& snapshot);
}
