# MecchaCamouflage — UE5.6 移植说明

## 概述

本文档记录将 MecchaCamouflage 从原版（针对早期 UE 版本）移植到 **Unreal Engine 5.6 + RE-UE4SS 3.x** 所做的全部适配工作。项目目标游戏为 **MECCHA CHAMELEON**（Steam，UE5.6 编译产物）。

---

## 1. 项目构建系统适配

### 1.1 CMakeLists.txt — C++ 标准升级至 C++23

```cmake
set_property(TARGET MecchaCamouflage PROPERTY CXX_STANDARD 23)
```

UE5.6 内部大量使用 C++20/23 特性（`std::ranges`、`std::bit_cast` 等）。将项目标准统一到 C++23 可避免头文件包含时的 ABI 冲突，并启用 `if consteval`、`std::expected` 等在 MSVC 19.34+ 上可用的语言特性。

### 1.2 RE-UE4SS 版本要求

本项目依赖 **RE-UE4SS 3.x**（需克隆到 `external/RE-UE4SS` 或通过 `UE4SS_ROOT` 指定）。UE4SS 2.x 不兼容 UE5.x 的 `FProperty` 体系，必须使用 3.x。

```powershell
# 构建命令（Ninja + MSVC）
.\scripts\build.ps1 -BuildType Game__Shipping__Win64
```

---

## 2. UE5.x 核心 API 变更

### 2.1 `FObjectPropertyBase` 虚函数访问器在 UE5.6 Shipping 中不可用

**位置**: `dllmain.cpp`, `write_object()` 函数（原 ~1339 行）

UE4SS 的 `FObjectPropertyBase::GetPropertyValue()` / `SetPropertyValue()` 虚函数在 UE5.6 Shipping 构建产物中无法通过 vtable 调用（函数表布局已变更）。

**解决方案**: 对 Object/ObjectPtr/Class 属性直接进行指针大小的原始内存读写：

```cpp
// ❌ 旧方式（UE4/早期 UE5）
auto* obj_prop = CastField<FObjectPropertyBase>(property);
obj_prop->SetPropertyValue(dest, value);   // UE5.6 Shipping 崩溃

// ✅ 新方式（UE5.6 Shipping 安全）
*reinterpret_cast<UObject**>(prop_value_ptr(container, property)) = value;
```

ProcessEvent 参数 slab 中的 Object/ObjectPtr/Class 参数均为指针大小，直接写入安全可靠。

---

### 2.2 `FHitResult::Actor` 字段重命名为 `HitObjectHandle`（UE5.3+）

**位置**: `dllmain.cpp`, `extract_hit()` 函数

从 UE5.3 起，`FHitResult` 的 Actor 引用从：

```cpp
TWeakObjectPtr<AActor> Actor;   // UE4 / UE5 早期
```

改为：

```cpp
FActorInstanceHandle HitObjectHandle;   // UE5.3+
```

`FActorInstanceHandle` 是一个 **UStruct**，不是 ObjectProperty，因此直接调用 `read_object_from_struct(..., "HitObjectHandle")` 只会返回 `nullptr`。

**解决方案（本次修复）**: 发现 `HitObjectHandle` 后，将其视为 `FStructProperty`，再从该结构体内部读取名为 `Actor` 的 `TWeakObjectPtr<AActor>` 字段：

```cpp
// UE5.3+ FHitResult::HitObjectHandle (FActorInstanceHandle) 深层读取
if (auto* handle_prop = CastField<FStructProperty>(
        find_struct_property(hit_struct, STR("HitObjectHandle"))))
{
    const auto* handle_struct = struct_type(handle_prop);
    auto* handle_base = prop_value_ptr(hit_base, handle_prop);
    hit.actor = read_object_from_struct(handle_struct, handle_base, STR("Actor"));
}
```

---

### 2.3 `FVector` / `FRotator` 精度从 `float` 改为 `double`（UE5.0+）

**位置**: 全文件，所有向量/旋转体运算

UE5.0 起 `FVector`、`FRotator`、`FTransform` 等核心数学类型从 `float`（32 位）改为 `double`（64 位）。

本项目全程使用 `double` 精度，通过 UE4SS 提供的 accessor 方法而非原始内存布局访问字段：

```cpp
FVector v = ...;
double x = v.X();   // ✅ 双精度 accessor（UE4SS 抽象层）
double y = v.Y();
double z = v.Z();

// StaticSize() 验证：UE5 FVector = 24 字节（3 × double），UE4 = 12 字节（3 × float）
static_assert(FVector::StaticSize() == 24);
```

---

### 2.4 `FScriptArray` API 增加 alignment 参数（RE-UE4SS 3.x）

**位置**: `dllmain.cpp`, 所有 FScriptArray 操作

RE-UE4SS 3.x 对应 UE5 的 `FScriptArray` 方法需要显式传入元素大小和对齐参数：

```cpp
// ❌ UE4SS 2.x（无 alignment 参数）
array->Empty(0, inner->GetSize());

// ✅ RE-UE4SS 3.x（必须传 alignment）
array->Empty(0, inner->GetSize(), inner->GetMinAlignment());
array->AddZeroed(count, inner->GetSize(), inner->GetMinAlignment());
```

---

### 2.5 Hook 注册 API 升级至 `TCallbackIterationData` / `FCallbackOptions`（RE-UE4SS 3.x）

**位置**: `dllmain.cpp`, `on_begin_play()` 和 Tick 回调注册处

RE-UE4SS 3.x 引入了新的类型安全 Hook 注册 API：

```cpp
// ✅ RE-UE4SS 3.x
RC::Unreal::Hooks::RegisterGameViewportClientTickPostCallback(
    [](RC::Unreal::FCallbackOptions& options,
       RC::Unreal::TCallbackIterationData<RC::Unreal::UGameViewportClient*>& data)
    {
        // tick logic
    });
```

旧式 `void*` 回调函数签名在 RE-UE4SS 3.x 中已移除。

---

### 2.6 `SpawnActor` 函数签名（UE5 兼容）

**位置**: `dllmain.cpp`, `spawn_scene_capture()` 函数

UE5 中 `UWorld::SpawnActor` 通过反射调用，参数为指针形式：

```cpp
// UE5 签名（通过 ProcessEvent）
UObject* SpawnActor(UClass* class, FVector* location, FRotator* rotation, ...)
```

本项目正确使用 `FVector*` 和 `FRotator*` 指针参数，与 UE5 ABI 一致。

---

### 2.7 `StaticConstructObject_Internal` 特征码扫描（UE5.6 适配）

**位置**: `UE4SS_Signatures/StaticConstructObject.lua`

UE5.4+ 的 `FStaticConstructObjectParameters` 结构体字段偏移发生变化，原特征码中的固定偏移字节（`8B 41 70`）在 UE5.6 编译产物中已失效。

**解决方案**: 将后段可变偏移字节替换为通配符 `??`，锚定函数序言前 22 字节作为主要识别段：

```lua
-- UE5.6 适配特征码（通配化后段）
return "4C 8B DC 55 53 41 56 49 8D AB 28 FE FF FF 48 81 EC C0 02 00 00 "
    .. "48 8B 05 ?? ?? ?? ?? 48 33 C4 48 89 85 A0 01 00 00 "
    .. "?? 8B ?? ?? 33 DB 49 89 ?? ?? 49 89 ?? ?? 48 8B F9 4D 89 ?? ??"
```

---

## 3. 本次新增修复（代码变更）

### 3.1 `read_number` / `write_number` — 新增完整整数属性类型支持

**位置**: `dllmain.cpp`, ~1230 行 / ~1345 行

UE5.6 中更多内部属性使用 64 位及小整数类型。原实现仅覆盖 `IntProperty`、`UInt32Property`、`ByteProperty`/`EnumProperty`。

**新增支持的属性类型**:

| 属性类型 | C++ 类型 | 说明 |
|---|---|---|
| `Int64Property` | `int64_t` | UE5 时间戳、索引等 |
| `UInt64Property` | `uint64_t` | ID、位掩码 |
| `Int16Property` | `int16_t` | 压缩坐标 |
| `UInt16Property` | `uint16_t` | 压缩法线、UV |
| `Int8Property` | `int8_t` | 字节标志 |

### 3.2 `extract_hit` — 修复 `FHitResult::HitObjectHandle` Actor 提取（详见 §2.2）

旧代码错误地将 `FActorInstanceHandle`（UStruct）作为 ObjectProperty 读取，导致 `hit.actor` 始终为 `nullptr`。新代码正确地向下钻取 FActorInstanceHandle 内部的 `TWeakObjectPtr<AActor>` 字段，确保碰撞过滤逻辑（owner_hit 检测）在 UE5.3+ 中正常工作。

---

## 4. 功能验证清单

| 功能点 | UE5.6 状态 | 说明 |
|---|---|---|
| Mod 加载（UE4SS 注入） | ✅ 正常 | RE-UE4SS 3.x 初始化 |
| F10 触发 UI 流程 | ✅ 正常 | Viewport Tick Hook |
| Scene Capture 生成 | ✅ 正常 | SpawnActor + UE5 签名 |
| Render Target 读取 | ✅ 正常 | KismetRenderingLibrary::ReadRenderTargetRaw |
| 颜色校准（Bulk Calibrate） | ✅ 正常 | 双精度 FVector 数学 |
| UV 刷子涂装 | ✅ 正常 | RuntimePaintableComponent 反射 |
| 碰撞命中检测 | ✅ 修复 | HitObjectHandle 深层读取（本次修复） |
| 数值属性读写 | ✅ 扩展 | 覆盖 64/16/8 位整数类型（本次修复） |
| 特征码扫描 | ✅ 正常 | UE5.6 通配符版本 |

---

## 5. 构建与安装

### 构建前提

- Visual Studio 2022（MSVC v143，x64）
- CMake ≥ 3.25
- Ninja（推荐）或 MSBuild
- RE-UE4SS 克隆到 `external/RE-UE4SS`

### 构建命令

```powershell
.\scripts\build.ps1 -BuildType Game__Shipping__Win64
```

产物位于 `build/cppmods/MecchaCamouflage/main.dll`。

### 安装路径

```text
<Steam>\steamapps\common\MECCHA CHAMELEON\
  Chameleon\Binaries\Win64\
    dwmapi.dll          ← UE4SS 代理 DLL
    UE4SS.dll
    UE4SS-settings.ini
    Mods\
      mods.txt
      MecchaCamouflage\
        dlls\
          main.dll      ← 本 mod 产物
```

---

## 6. 文件变更摘要

| 文件 | 变更类型 | 说明 |
|---|---|---|
| `cppmods/MecchaCamouflage/src/dllmain.cpp` | 修改 | 3 处代码修复（见§3） |
| `UE4SS_Signatures/StaticConstructObject.lua` | 修改 | UE5.6 通配符特征码 |
| `CMakeLists.txt` | 修改 | C++23 标准，RE-UE4SS 依赖 |
| `scripts/build.ps1` | 修改 | Shipping 构建类型，版本检查关闭 |
