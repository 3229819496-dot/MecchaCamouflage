-- StaticConstructObject_Internal 特征码扫描脚本
-- 适配版本：Unreal Engine 5.6
-- 说明：
--   UE5.4+ 起 FStaticConstructObjectParameters 结构体字段偏移发生变化，
--   原特征码中的固定偏移字节（如 8B 41 70）在 UE5.6 已不再适用。
--   本版本将后段可变偏移字节替换为通配符 ??，以兼容 UE5.6 编译产物。
--
-- 原始特征码（UE4 / UE5 早期）：
--   4C 8B DC 55 53 41 56 49 8D AB 28 FE FF FF 48 81 EC C0 02 00 00
--   48 8B 05 ?? ?? ?? ?? 48 33 C4 48 89 85 A0 01 00 00
--   8B 41 70 33 DB 49 89 73 10 49 89 7B 18 48 8B F9 4D 89 63 20 44 8B 61 18
--
-- UE5.6 变更点：
--   1. FStaticConstructObjectParameters::Outer 等字段偏移在 UE5.4/5.5/5.6 中已更新，
--      原偏移 0x70（8B 41 70）改为通配处理
--   2. 后段寄存器保存顺序可能因 MSVC 版本差异略有不同，统一通配化
--   3. 函数序言（前 22 字节）在 UE5.x 中保持稳定，作为主要锚点

function Register()
    -- UE5.6 适配特征码
    -- 锚点：函数序言 + 栈帧分配 + Stack Cookie 检查（稳定段）
    -- 后段：参数偏移访问 + 寄存器保存（通配化以兼容 UE5.6 编译差异）
    return "4C 8B DC 55 53 41 56 49 8D AB 28 FE FF FF 48 81 EC C0 02 00 00 48 8B 05 ?? ?? ?? ?? 48 33 C4 48 89 85 A0 01 00 00 ?? 8B ?? ?? 33 DB 49 89 ?? ?? 49 89 ?? ?? 48 8B F9 4D 89 ?? ??"
end

function OnMatchFound(MatchAddress)
    -- 直接返回匹配到的 StaticConstructObject_Internal 函数地址
    return MatchAddress
end
