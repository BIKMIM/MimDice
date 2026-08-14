# MimDice 개발 가이드

이 문서는 **코드를 고치기 전에 먼저 읽는 문서**입니다.
2026년 8월, 와우 12.1(2시즌) 대응 과정에서 같은 종류의 실수를 여러 번 반복했습니다.
그 기록과 결론을 남겨서 다음에 같은 함정에 빠지지 않도록 합니다.

특히 **오라(버프/디버프) 관련 코드, 사운드 알림, 설정창 레이아웃**을 건드릴 때는 반드시 먼저 읽으세요.

---

## 0. 3줄 요약

1. **블러드 감지에 `C_UnitAuras.AddAuraSound` / `RemoveAuraSound` 등록 계층을 쓰지 않습니다.** `AddAuraSound` 차단은 `pcall`로도 막을 수 없습니다.
2. **오라 감지는 `C_UnitAuras.GetPlayerAuraBySpellID` 조회 방식**을 씁니다. 블러드 후유증은 전부 읽기 허용(NeverSecret)이라 제한 상황에서도 동작합니다.
3. **실제로 후유증을 받은 블러드 알림은 빠뜨리지 않습니다.** 불가피한 중복은 허용하지만, 시전만 보고 울려서도 안 됩니다.

현재 블러드 감지 구조는 **10장**에 있습니다. 블러드 코드를 건드린다면 거기부터 보세요.

---

## 1. 배경: 12.1 비밀 값(secret value)

12.1부터 전투 등 제한 상황에서 애드온이 오라 데이터를 읽지 못하게 막혔습니다.

### 무엇이 비밀이 되나

- `UNIT_AURA` 이벤트의 `updateInfo` 전체 또는 그 안의 `addedAuras`
- `AuraData` 구조체 전체 (남은 시간, 시전자 등)
- 상황에 따라 이벤트 인자(`unit`, `spellID`)도 비밀일 수 있음

### 비밀 값으로 하면 안 되는 것

비밀 값은 **읽기만 실패하는 게 아니라 건드리는 순간 Lua 오류**가 납니다.

- 비교 (`==`, `~=`, `<`)
- 산술 (`-`, `+`)
- 순회 (`ipairs`, `pairs`)
- 필드 접근 (`t.field`)

### 반드시 지킬 검사 순서

```lua
if type(issecretvalue) == "function" and issecretvalue(v) then return end  -- 1. 비밀인가
if type(v) ~= "string" then return end                                     -- 2. 형식이 맞나
if v == "player" then ... end                                              -- 3. 그제야 비교
```

**중요**: 비밀 문자열도 `type()`을 물어보면 `"string"`을 반환합니다.
그래서 `type()` 검사만으로는 절대 거를 수 없습니다. 비밀 검사가 항상 먼저입니다.

### pcall의 한계 (가장 비싸게 배운 교훈)

`pcall`은 **Lua 오류만** 잡습니다. 다음은 못 막습니다.

- `ADDON_ACTION_BLOCKED` (보호된 함수 호출 차단). 이건 오류가 아니라 클라이언트가 호출을 거부하고 따로 알리는 것입니다.
- 비밀 값을 조용히 건너뛰는 상황. 오류는 안 나지만 감지가 안 됩니다.

`pcall`을 붙였다고 안전해진 게 아닙니다. **무엇을 못 막는지**를 먼저 생각하세요.

---

## 2. 실측으로 확인된 사실

아래는 실제 클라이언트에서 확인한 2026-08-14 기준 스냅샷입니다. 대형 패치 뒤에는 확인 매크로를 다시 실행하세요.

### 애드온 제한 상태 (2026-08-14에 실측한 일반 던전 안, 비전투)

| 제한 종류 | 값 | 상태 |
|---|---|---|
| Map | 4 | **활성(2)** |
| Combat | 0 | 해제(0) |
| Encounter | 1 | 해제(0) |
| ChallengeMode | 2 | 해제(0), 쐐기 시작 시 활성 |
| PvPMatch | 3 | 해제(0) |
| Chat | 5 | 해제(0) |

**핵심**: 실측한 일반 던전에서는 쐐기가 아니어도 **Map 제한이 활성**이었습니다.
모든 던전과 향후 클라이언트가 영구히 같다고 단정하지 말고, 제한 여부와 무관하게 보호된 오라 사운드 등록에 의존하지 않습니다.

### 블러드 후유증 오라 비밀 등급

`C_Secrets.GetSpellAuraSecrecy(id)` 결과가 **7종 전부 `0`(NeverSecret)** 입니다.

| 주문 ID | 이름 |
|---|---|
| 57723 | Exhaustion (영웅심) |
| 57724 | Sated (피의 욕망) |
| 80354 | Temporal Displacement (시간 왜곡) |
| 95809 | Insanity (고대의 광기) |
| 160455 | Fatigued (여진풍) |
| 264689 | Fatigued (원시의 격노) |
| 390435 | Exhaustion (분노한 위상) |

**결론**: 제한 상황에서도 이 오라들은 정확 주문 ID 조회로 읽을 수 있습니다.
보호된 `AddAuraSound`를 쓸 이유가 없습니다.

### 확인용 매크로 (게임에서 직접 실행)

```
/run for k,v in pairs(Enum.AddOnRestrictionType) do print(k,v,C_RestrictedActions.GetAddOnRestrictionState(v)) end
/run for _,id in ipairs({57723,57724,80354,95809,160455,264689,390435}) do print(id,C_Secrets.GetSpellAuraSecrecy(id)) end
```

- 제한 상태: `0`=해제, `1`=적용 중, `2`=활성
- 비밀 등급: `0`=항상 읽기 가능, `1`=항상 비밀, `2`=상황에 따라 비밀

---

## 3. 검증된 다른 애드온의 방식 (따라야 할 본보기)

같은 기능을 구현한, 사용자가 훨씬 많은 애드온 두 개를 확인했습니다.
**둘 다 `AddAuraSound`를 전혀 쓰지 않습니다.**

### ActionSounds 3.6.1

`Features/Bloodlust/BloodlustDetector.lua`, 전체 60줄.

1. `UNIT_AURA`를 신호로만 받음 (payload는 읽지 않음)
2. `GetPlayerAuraBySpellID`로 후유증 목록을 직접 조회
3. 없음에서 있음으로 바뀌고 남은 시간이 560초 이상이면 발동
4. `PLAYER_ENTERING_WORLD`에서는 현재 상태를 기준값으로만 저장 (발동 안 함)

보호된 오라 사운드 등록 없이 동작합니다. 후유증이 NeverSecret이기 때문입니다.

### EnhanceQoL 12.1.0

- **판단**은 `GetPlayerAuraBySpellID` + `GetSpellAuraSecrecy` 사전 확인 (`EnhanceQoLMythicPlus.lua`의 `getActiveBloodlustAura`)
- **표시**만 블리자드의 AuraContainer 사용
- MimDice의 `SA_QueryBloodlustAuraPresence`와 거의 동일한 구조

---

## 4. 지금까지 한 실수 기록

### 블러드 감지

| 버전 | 무엇을 했나 | 무엇이 문제였나 |
|---|---|---|
| ~1.15.6 | `updateInfo.addedAuras`를 직접 순회 | 제한 전투에서 `ipairs` 자체가 오류. 블러드 알림 완전 사망. 오류 표시가 기본 꺼짐이라 사용자는 조용히 안 되는 것만 겪음 |
| 1.15.7~1.15.8 | `pcall` 우회, 시전 ID, 긴 중복 잠금, `AddAuraSound`를 함께 도입·보완 | 실제 적용 여부가 아닌 시전에 의존하고, 긴 잠금은 전멸 후 재블러드를 누락. SoundKit ID는 사용자가 고른 소리 대신 번들 음원이 나가는 부작용 |
| 1.15.9 | 제한 중에도 등록 강행, 제한 변경마다 재등록 | **`ADDON_ACTION_BLOCKED` 발생**. 던전 퇴장 시 가짜 바까지 |
| 1.15.10 | `ShouldAurasBeSecret()`으로 등록 차단 | 판단 기준이 틀림. 등록을 막는 건 애드온 제한 상태지 오라 비밀 여부가 아님. Map 제한을 놓침 |
| 1.15.11 개발 중간 | `GetAddOnRestrictionState`로 직접 추적 + 로딩 구간 잠금 | 차단 오류는 피하지만 native를 유지하기 위한 상태 관리가 과도해 배포 전 폐기 |
| 1.15.11 최종 | **native 제거, 정확 ID 조회만 유지** | 보호 함수 오류와 등록 시점 문제를 구조적으로 제거 |

### 그 밖의 실수

- **파티 신청 알림**: 묶음 신청(여럿이 함께 지원)에서 1번 멤버만 조회해 첫 사람 이름만 반복 표시. 반복 알림도 같은 사람만 재표시. 데이터 도착 전에 "알림함" 처리해서 이름을 영영 놓침. `LFG_LIST_APPLICANT_UPDATED` 미구독.
- **기본값**: 신규 사용자에게 블러드 알림이 기본 꺼짐이라 "설치했는데 안 울린다"는 제보로 이어짐.
- **주문 ID 목록 관리**: 북(Drums) 계열이 대거 누락. 특히 2시즌 신규 북이 빠져 있었음. 시전 ID 목록에 의존하는 감지는 매 시즌 관리 비용이 듦.
- **설정창 레이아웃**: 안내 문구를 넣으면서 그 아래 항목들의 좌표를 안 내려서 버튼이 겹침. 창 높이(접힘/펼침)도 같이 조정해야 함.

---

## 5. 절대 규칙

### 하지 말 것

- 블러드 감지를 위한 `AddAuraSound` / `RemoveAuraSound` 등록 계층. `AddAuraSound` 차단은 `pcall`로 못 막습니다.
- 비밀일 수 있는 값을 검사 없이 비교/순회/연산
- 팝업 경고창으로 사용자를 놀래키기
- 기존 사용자의 저장된 설정을 강제로 바꾸거나 지우기
- 시전 이벤트 ID 목록에만 의존하는 감지 (매 시즌 깨짐)

### 할 것

- 오라 감지는 정확 주문 ID 조회 + 없음에서 있음 전이
- 지역 이동/로딩 구간에는 발동을 잠시 잠그기 (오라 재전송을 새 발동으로 오인 방지)
- 진입 시점에는 현재 상태를 기준값으로만 저장하고 발동하지 않기
- 확실하지 않으면 게임에서 매크로로 직접 확인하기
- 같은 기능을 구현한 다른 애드온과 비교하되, 인기도만 믿지 말고 API 문서와 게임 실측으로 다시 검증하기

---

## 6. 수정 전 체크리스트

- [ ] 오라/이벤트 인자를 다루는가? 비밀 검사가 비교보다 **먼저** 오는가
- [ ] 보호된 함수를 호출하는가? 그렇다면 다른 방법이 없는지 다시 검토
- [ ] `pcall`을 붙였는가? 그게 무엇을 못 막는지 설명할 수 있는가
- [ ] 새 UI 요소를 넣었는가? 그 아래 모든 항목의 좌표와 창 높이를 조정했는가
- [ ] 기본값을 바꿨는가? 신규 사용자와 기존 사용자 양쪽 결과를 확인했는가
- [ ] 주문 ID 목록을 건드렸는가? 이번 시즌 신규 아이템을 확인했는가
- [ ] 알림이 빠질 수 있는 경로가 새로 생기지 않았는가
- [ ] 실제 적용된 오라가 아니라 시전 이벤트만 보고 알리게 바뀌지 않았는가

---

## 7. 배포 절차

1. **버전을 3곳 모두** 수정
   - `MimDice.toc` → `## Version:`
   - `MimDice.lua` → `-- Version        : v`
   - `MimDice.xml` → `text="v "`
2. Lua 문법 검사 통과 확인
3. 게임에서 `/reload` 후 실제 동작 확인 (아래 테스트 항목)
4. 커밋 메시지는 한국어로 작성
5. **푸시는 사용자가 명시적으로 요청할 때만**
6. CurseForge는 `Add File`로 새 zip 업로드
   - zip 최상위는 `MimDice` 폴더 하나
   - `.vscode` 등 개발용 파일 제외
   - Game versions에 현재 인터페이스 버전 체크

### 배포 전 게임 테스트 (블러드 관련 수정 시)

1. **마을에서 `/reload` 후 걸어서 던전 입장** → 지역 이동 뒤에도 블러드 소리와 바가 나오는가
2. **던전 안에서 `/reload`** → 재접속 기준선 저장 뒤 새 블러드 소리와 바가 나오는가
3. **블러드 직후 던전 나가기** → 가짜 바가 뜨지 않는가
4. **생명석 사용, 전투 종료** → BugGrabber에 오류가 없는가
5. 테스트 중에는 ActionSounds의 블러드 알림을 꺼서 소리를 구분
6. **죽음·사거리 밖·기존 후유증 보유 상태에서 다른 사람이 블러드 시전** → 소리와 새 바가 나오지 않는가
7. 내장·커스텀·효과음 번호 중 실제 사용 설정으로 테스트 → 선택한 소리가 정확히 한 번 나오는가

---

## 8. 설계 우선순위 (사용자가 정한 것)

1. **실제 적용 알림 누락 방지가 우선.** 불가피한 중복은 허용합니다. 단, 죽음·사거리 밖·기존 후유증 때문에 블러드를 받지 못했다면 울리지 않습니다.
2. **조용한 애드온.** 팝업 금지. 안내가 필요하면 해당 설정 옆에 작은 글씨로.
3. **쉬운 한국어.** 사용자에게 보이는 문구에 전문 용어를 쓰지 않습니다.
4. **기존 설정 보존.** 업데이트가 사용자의 선택을 지우지 않습니다.

---

## 9. 참고 위치

- 블러드 감지: `SoundAlert.lua`의 `SA_QueryBloodlustAuraPresence`, `SA_SyncBloodlustAuraPresence`, `SA_TriggerBloodlust`
- 파티 신청 알림: `SoundAlert.lua`의 `SA_CheckPartyApplicants`, `SA_PartyApplicantText`
- 본보기 애드온
  - `../ActionSounds/Features/Bloodlust/BloodlustDetector.lua`
  - `../EnhanceQoLDungeonRaid/EnhanceQoLMythicPlus.lua` (`getActiveBloodlustAura`)
- API 문서: https://warcraft.wiki.gg/wiki/Secret_values
- Blizzard 생성 API 문서
  - `UnitAuraDocumentation.lua`: https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitAuraDocumentation.lua
  - `RestrictedActionsDocumentation.lua`: https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/RestrictedActionsDocumentation.lua

---

## 10. 현재 블러드 구조 (1.15.11)

2026-08-14 기준 합의하고 코드에 반영한 구조입니다.

### 제거 완료

- `C_UnitAuras.AddAuraSound` / `RemoveAuraSound` 호출 전체
- native 상태값 3종: 준비 완료 여부, 등록 대기(pending), 대체 음원 사용 여부
- 애드온 제한 상태 6종 추적 (`GetAddOnRestrictionState` 관련 전체). native 등록 때문에만 필요했던 장치입니다
- SoundKit ID 노란 안내 문구와 번들 음원 대체 로직. native가 그 형식을 못 받아서 생긴 제약이므로 같이 사라집니다
- 블러드 시전 이벤트로 직접 발동하는 경로. 죽었거나, 사거리 밖이거나, 이미 후유증이 있어서 실제로는 블러드를 못 받은 상황에서 잘못 울리는 문제가 없어집니다

### 남길 것

- 후유증 7종의 `GetPlayerAuraBySpellID` 조회와 없음에서 있음 전이 판정
- 진입 시 기존 후유증을 기준값으로만 저장, 560초 판정
- 로딩 시작부터 지역 입장 후 3초까지 발동 차단
- `UNIT_SPELLCAST_SUCCEEDED` **이벤트 자체**. 사용자 지정 주문 알림에서 계속 사용합니다. 블러드 발동 부분만 걷어냅니다

### 앞으로 지키기

- **`SA_AuraEnvironmentRestricted`는 지우면 안 됩니다.** 정확 조회 쪽(`SA_ShouldAurasBeSecret` → `SA_QueryBloodlustAuraPresence`)에서 제한 중 NeverSecret 사전 확인에 씁니다.
- `SA_TriggerBloodlust`는 native 상태 인자를 받지 않습니다. 호출되면 사용자 설정에 맞는 소리와 진행바를 함께 처리합니다.
- `UNIT_AURA`의 `updateInfo`는 읽지 않습니다. 이벤트는 조회를 시작하는 신호로만 사용합니다.

### 이번에 바로잡은 오해

- 실측한 던전의 Map 제한은 **새 등록을 막는 상태**였습니다. 입장 전에 등록해 둔 소리가 무효가 된다는 뜻은 아닙니다.
- native 소리가 안 나도 진행바까지 사라지지는 않습니다. 조회 경로가 진행바를 따로 시작합니다.
- `160455`(여진풍 피로)는 이미 후유증 목록에 들어 있습니다.
