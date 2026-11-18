# 밈다이스 차단 성공 알림 수정 가이드

작성 기준: 2026-11-17, `D:\Dev\MimDice` 및 본섭에 설치된 EllesmereUI·EXBoss 소스 확인.
이 문서는 클로드에게 전달할 구현 명세다. 이번 작업에서는 애드온 동작 코드를 수정하지 않았다.

## 1. 목표와 작업 경계

목표는 **다른 사람이 먼저 차단했거나 아무것도 차단하지 못했는데 밈다이스가 내 차단 성공 소리를 내는 현상**을 막는 것이다.

- 확실한 내 성공, 확실한 타인 성공, 확인 불가능을 구분한다. 확인 불가능을 성공으로 승격하지 않는다.
- 확인 불가능할 때 소리를 생략하는 것은 이 수정안의 보수적인 설계 선택이다. 사용자가 블러드에 정한 누락 방지 원칙을 차단 기능의 추정 성공 허용으로 확대하지 않는다.
- 공개된 정보로 확인되는 내 성공은 유지한다. 제한 구역에서도 검증된 증거가 있으면 알리되, 모든 성공을 감지한다고 약속하지 않는다.
- 변경 전 `AGENTS.md`, `DEVGUIDE.md`, 현재 diff를 읽는다. 현재 `MimDice.lua`에 사용자 수정이 있으므로 보존한다.
- 주 수정 대상은 `SoundAlert.lua`의 차단 감지와 그 테스트다. 별도 모듈로 분리한다면 TOC 로딩 순서 및 기존 테스트의 주입 지점을 함께 확인한다.
- 블러드·마력 주입·전투부활·파티·채팅 알림 및 저장된 소리 설정은 유지한다. AddAuraSound 등록을 추가하지 않는다.
- 이번 문서는 구현 및 검증용이다. 커밋·버전 변경·게임 폴더 배포·푸시는 별도 요청 범위에 따른다. 배포 시 버전 3곳 규칙을 지킨다.

## 2. 리뷰에서 채택할 점과 정정할 점

### 현재 밈다이스에서 확인한 문제

`SoundAlert.lua`의 다음 심볼을 기준으로 현재 파일을 다시 찾는다. 줄 번호는 수정 후 달라진다.

- `SA_RecordInterruptAttempt`: 내 차단기 사용 시 0.25초의 시도 기록을 만든다.
- `SA_HandleInterruptResult`: `interruptedBy`가 비밀이면 내 GUID 확인 없이 통과한다.
- `SA_divineTollExpiresAt` 분기: 0.35초 안의 중단 신호를 차단자 확인 전에 성공 처리한다. 공개된 타인 GUID나 nil도 여기서 걸러지지 않는다.
- `SA_IsInterruptTargetUnit`: 여러 적 토큰을 허용하고, 비밀 토큰도 허용한다. 특정 적에 대한 시도와 해당 적의 결과를 연결하는 증거는 아니다.
- `UNIT_SPELLCAST_CHANNEL_STOP`도 같은 처리기로 들어온다. 자연 종료 신호를 차단 성공으로 해석해서는 안 된다.

클로드 리뷰의 핵심 원인과 A/B/C의 장단점은 대체로 맞다. 다만 `interruptedBy=nil`인 자연 종료는 일반 차단 분기의 공개 값 형식 검사에서 이미 거른다. 현재 명확한 누락은 **그 검사보다 앞선 신성한 종 분기**다.

### 엘스미어에서 실제로 더 확인한 내용

참고 파일:

`D:\Games\World of Warcraft\_retail_\Interface\AddOns\EllesmereUIMythicTimer\EUI_MythicTimer_KickEngine.lua`

| 위치/심볼 | 확인한 동작 | 밈다이스에 적용할 판단 |
| --- | --- | --- |
| `ReadSource`, `ReadRows` (약 584~665행) | 미터의 행 정보와 GUID별 breakdown 길이를 읽는다 | 안전하게 읽을 수 있는 증거만 독립적으로 수집하는 구조를 참고 |
| `Attribute` (약 1257~1326행) | 이전 snapshot과 새 snapshot을 비교하고 중단 이벤트와 연결한다 | 기준선·세션·이벤트 순서 관리 채택 |
| `Decide` (약 1136~1185행) | 목록 증가, 새 행, 행 순서, 시전 등으로 후보를 결정한다 | 증거별 강도 구분은 참고하되 결과를 그대로 신뢰하지 않음 |
| `Decide`의 `OwnPending` 대체 경로 | 다른 결정적 정보가 없으면 최근 내 시전을 `how="cast"`로 선택하며 `sure`에도 포함 | **가져오지 말 것. 이번 오탐의 원인과 같은 추정이 남는다** |
| `OnOwnCast` (약 1427행) | 시전만으로 본인 아이콘·쿨타임 모델을 갱신하고 kick 이벤트를 보낸다 | 그 콜백을 사운드 성공 신호로 사용하지 않음 |
| 파일 앞부분 및 `KickPlates.lua`의 `Gate` | 비밀 숫자를 StatusBar와 clipping에 넘겨 화면 표시를 제어 | Lua가 증가 여부를 읽는 성공 판정과 다름. 사운드 조건으로 재활용하지 않음 |

앞선 Codex 답변은 엘스미어의 숫자 집계 위주로 설명하여 이 KickEngine을 빠뜨렸다. 제미나이 리뷰는 이 파일을 찾은 점이 유용하지만 다음 단정은 채택하지 않는다.

- “엘스미어는 항상 서버가 정한 차단자를 Lua에서 정확하게 판별한다”: 자체 추론·시전 대체 경로도 있다.
- “같은 프레임 이벤트는 API가 보장한다”: 설치 코드의 관측과 가정이다. 공식 이벤트 순서 계약으로 확인되지 않았다.
- “내 행 부재는 100% 남의 차단”: 조회 실패, 지연, 소환수 별도 집계, 세션 교체가 가능하다.
- “남의 목록 증가면 내 차단 실패”: 다른 적에서 두 사람이 동시에 성공했을 수 있다.
- “행 순위 상승이면 100% 내 성공”: 정렬·동률·행 추가/삭제·snapshot 누락 조건을 검증해야 한다.
- “combatSpells 길이 = 차단 횟수”: 서로 다르다. 같은 주문 반복 차단은 길이가 그대로일 수 있다. 배열 항목 의미도 실측한다.
- “마법 반사 = 일반 차단기”: 기존 목록에도 없다. 반사·당기기·침묵·기절을 이번 작업에서 임의로 같은 의미로 확장하지 않는다.

### EXBoss에서 채택할 점

참고 파일:

- `...\EXBoss\Modules\Tools\InterruptTracker.lua`: `AddInterruptRecord`, `HandleInterruptEvent` (약 423~477행)
- `...\ExwindCore\Core\ExwindState.lua`: `UNIT_SPELLCAST_SUCCEEDED` 기반 본인 차단 쿨타임 처리 (약 1743행)

EXBoss는 시전 후 쿨타임 표시와 실제 중단 이벤트의 차단자 표시를 구분한다. 비밀 차단자 GUID를 이름/직업 API와 표시 함수에 넘기는 방식은 “비밀 값을 읽지 않고 표시하기”의 참고다.

그러나 표시 가능한 비밀 이름을 내 이름과 비교해서 사운드를 내는 것은 별개다. 현재 설치 코드에는 nameplate 필터와 `UnitTokenFromGUID` 결과에 따른 표시 조건도 있으므로 “모든 차단이 무조건 표시된다”고 해석하지 않는다. 그 코드의 비밀 값 직접 nil 비교도 복사하지 않는다.

## 3. 사용할 API와 비밀 값 처리

공식 생성 문서:

https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/DamageMeterDocumentation.lua

확인한 API와 payload:

```text
C_DamageMeter.GetCombatSessionFromType(sessionType, meterType)
C_DamageMeter.GetCombatSessionSourceFromType(sessionType, meterType, sourceGUID, sourceCreatureID)
C_DamageMeter.IsDamageMeterAvailable()

sessionType = Enum.DamageMeterSessionType.Current
meterType   = Enum.DamageMeterType.Interrupts

DAMAGE_METER_COMBAT_SESSION_UPDATED: meterType, sessionID
DAMAGE_METER_CURRENT_SESSION_UPDATED
DAMAGE_METER_RESET
```

생성 문서에서 세션 조회는 `SecretWhenInCombat`이다. 행의 `isLocalPlayer`, `classFilename`, `specIconID`에는 `NeverSecret` 표기가 있다. 따라서 “모든 데이터를 읽을 수 있다”와 “아무 필드도 읽을 수 없다” 모두 잘못된 전제다. 구조 접근 가능 여부와 필드별 비밀 여부를 따로 확인한다. 전투 중 실제 동작은 해당 클라이언트에서 검증한다.

안전 규칙:

1. 비밀 값 검사 → 형식 검사 → 비교/산술/인덱싱 순서. nil 검사도 직접 비교 전에 비밀 여부를 확인한다.
2. `type(v)=="string"`만으로 공개 문자열이라고 판단하지 않는다.
3. 기존 `SA_IsSecret`은 `hasanysecretvalues`까지 호출한다. 비밀 자식 필드가 있는 공개 컨테이너에 이를 적용하면 읽을 수 있는 NeverSecret 메타데이터까지 전부 버릴 수 있다.
4. 미터 읽기 전용 보조 함수를 둔다. 컨테이너 자체가 비밀인지 `issecretvalue`로 검사하고, 공개 table일 때만 필요한 필드를 접근한다. 각각의 필드는 다시 검사한다. 기존 공용 `SA_IsSecret`의 의미를 전역 변경하지 않는다.
5. 중첩 table도 접근 전 검사한다. `#`, 순회, 행 인덱싱은 접근 가능한 table에만 한다. 계산된 길이도 공개 number인지 확인한 뒤 사용한다.
6. `pcall` 성공은 반환값 공개나 조회 완료의 증거가 아니다. API 오류를 격리하고 반환 구조를 따로 검증한다. 오류를 빈 목록이나 0회 성공으로 바꾸지 않는다.
7. 비밀 GUID/주문 ID를 테이블 키로 쓰거나 `tostring`, format, 비교, 산술에 넣지 않는다. 로그도 마찬가지다.
8. `UnitTokenFromGUID`가 비밀 GUID를 받는다고 공개 token을 돌려준다는 보장은 없다. 공개 token이 확인될 때만 다음 비교를 한다. 반환값이 다시 비밀이면 미확인이다.
9. UI의 `GetWidth`, `GetValue`, `IsShown`, clipping 결과 등으로 비밀 숫자를 역으로 읽어 사운드를 결정하는 우회는 추가하지 않는다.
10. API/Enum이 없거나 비활성이면 해당 증거 공급원만 unavailable 처리한다. 이벤트 처리기 전체나 다른 알림 기능을 중단하지 않는다.

## 4. 성공 판정 정책

| 증거 | 상태 | 소리 |
| --- | --- | --- |
| 유효한 내 시도와 연결된 공개 차단자 GUID가 내 캐릭터/해당 소환수 GUID와 일치 | confirmed_self | 1회 |
| 그 결과의 공개 차단자 GUID가 타인 | confirmed_other | 해당 결과로는 재생 금지 |
| 같은 세션의 검증된 내 source에서 공개 totalAmount가 실제 증가 | confirmed_self 후보 | 유효한 시도·중단 결과와 연결되고 중복이 아니면 1회 |
| 내 source의 검증된 breakdown 길이 증가, 또는 검증된 내 첫 행 출현 | metadata_self 후보 | 1차 수정에서는 진단만. 아래 실측 조건 충족 후 제한적으로 사용 |
| 내 행 순위 변화만 있음 | supporting_only | 단독 재생 금지 |
| 타인 변화만 관측되거나 내 행이 아직 없음 | unknown 또는 타인 증거 | 내 실패 확정 금지. 내 추가 증거를 기다림 |
| 최근 내 시전 + 비밀 차단자 + 시간 근접뿐 | unknown | 재생 금지 |
| 비밀 차단 횟수를 위젯에서만 표시할 수 있음 | unknown | 재생 금지 |
| 자연 종료/공개 nil·빈 차단자 | not_interrupt | 재생 금지 |

핵심은 **타인의 증가가 없다는 이유로 내 성공이라고 판정하지 않는 것**이다. 증거가 충분하지 않은 성공 누락은 진단에 남기고, 기존 시간 추정을 fallback으로 복구하지 않는다.

메타데이터 실측 후 사용 조건:

- 내 캐릭터 또는 현재 내 소환수의 공개 GUID로 조회한 source임이 확인된다. class+spec만 같은 행을 내 소환수로 간주하지 않는다.
- 전후 snapshot이 모두 조회 성공이고, 같은 세션·같은 source이며, 기준선은 시도와 관련된 갱신 이전에 확보돼 있다.
- 증가한 배열이 실제 차단 기록이라는 것을 반복 실측한다. 기존 기록 초기 로딩·지연 해제·부분 조회 해소가 아니다.
- 유효한 내 차단기 시도와 차단자 값이 존재하는 적 중단 신호를 함께 확보한다.
- 당기기/스턴 등 별도 행동의 미터 기록이 내 차단기 시도와 겹친 사례도 검사한다. 설치 엘스미어는 당기기 기록을 따로 거르는 분기가 있다. “미터 증가 = 이 차단기의 성공”으로 단정하지 않는다.
- 어느 조건이든 불명확하면 unknown을 유지한다. 검증 전에는 배포용 성공 조건에 넣지 않는다.

이 보수적인 정책으로도 같은 주문을 반복 차단하여 목록·순위가 변하지 않고 숫자마저 비밀이면 확인할 수 없다. 이를 정상적인 기술적 한계로 보고한다. “겹짤을 완전히 구분하면서 기존 모든 성공 소리를 보존”했다고 보고하지 않는다.

## 5. 권장 구현 순서

### 1단계: 현재 오탐 경로 제거

- 신성한 종 특례보다 먼저 차단자 값의 유효성을 검사한다.
- 공개 nil/빈 문자열/잘못된 형식은 무시한다. 비밀 값이면 직접 nil·문자열 비교를 하지 않고 증거 대기로 보낸다.
- 일반 차단과 신성한 종 모두 같은 성공 검증 경로를 통과하게 한다.
- 공개 GUID가 내 시도 source와 일치할 때만 즉시 확정한다. 비밀 GUID는 시간만으로 재생하지 않는다.
- 신성한 종은 시도 source를 `player`로 명시하고 동일한 중복 방지 규칙을 쓴다.
- 시전 시간창은 오래된 기록 제거와 투사체 대기에만 쓴다. 짧은 시간차 자체는 성공 증거가 아니다.
- 공개 타인의 결과 하나를 봤다고 전체 내 시도를 지우지 않는다. 다른 적에서 내 결과가 뒤이어 올 수 있다.

### 2단계: 읽기 전용 미터 진단

- 기능 활성 중에만 필요한 미터 이벤트를 구독하고 baseline을 유지한다. 주기적인 전체 파티 polling은 추가하지 않는다.
- 처음에는 내 캐릭터와 내 소환수 source를 중심으로 읽는다. 남의 쿨타임·특성·Inspect 모델 전체를 가져올 필요가 없다.
- 순위 비교를 연구할 때도 최대 파티 5명에 고정하지 않는다. 레이드·솔로에서 미지원이면 명시적으로 unknown 처리한다.
- `DAMAGE_METER_COMBAT_SESSION_UPDATED` 첫 인자가 Interrupts인지 안전하게 확인한다. payload sessionID를 Current 세션과 혼동하지 않는다.
- 이벤트만으로 Current 세션임이 식별되지 않는 환경에서는 진단만 하고 자동 성공 판정에 사용하지 않는다. 문서에 없는 `session.sessionID` 존재를 가정하지 않는다.
- 한 프레임 중복 갱신은 최종 snapshot을 읽도록 합칠 수 있다. 첫 이벤트만 읽고 뒤 이벤트를 전부 버리는 방식은 같은 프레임의 두 번째 차단을 놓칠 수 있다.
- API 오류/비밀/실제 빈 목록을 각각 구분한다. 읽기 실패 후 재개된 snapshot에서 과거 누적분을 새 성공으로 재생하지 않는다.
- 이 단계에서 단축키로 실행할 일회성 진단이나 기본 꺼짐의 진단 명령을 제공한다. 확인 없이 기존 성공 소리와 연결하지 않는다.

### 3단계: 검증된 증거만 성공 경로에 연결

- 공개 횟수 증가가 실제로 가능하면 같은 세션·source의 전후 차이를 우선 사용한다.
- 제한 구역에서 숫자가 비밀이면 검증된 구조 정보만 정책표대로 제한적으로 사용한다.
- 진단으로 입증하지 못한 후보 판정은 배포 경로에서 제외하고 한계를 보고한다. 오래 기다린다는 이유로 성공 처리하지 않는다.
- 쿨타임 감소, 즉시/투사체별 정밀 시간 모델은 별도 확장이다. 직업별 근거·특성·비밀 여부를 확인하기 전에는 이번 성공 조건으로 추가하지 않는다.
- 기존 주문 목록을 일단 보존하고, 스킬 분류 오류를 발견하면 근거와 함께 별도 변경으로 다룬다.

## 6. 상태와 이벤트 처리 명세

권장 상태는 작은 시도 목록과 결과/증거 목록이다. 전역 단일 GUID+만료값만으로 모든 source와 결과를 덮어쓰지 않는다.

```text
attempt:
  id, generation, sourceToken, publicSourceGUID, publicPetGUID,
  spellID, createdAt, deadline, baselineRevision, consumed

result:
  id, generation, receivedAt, eventKind,
  공개일 때만 저장하는 대상/cast 식별자,
  interrupterState(public_self/public_other/secret/absent), matched

snapshot:
  generation, revision, receivedAt, sessionIdentityKnown, validity,
  sourceIdentity, amountKnown, amount, breakdownLengthKnown, breakdownLength
```

- `unknown`과 실제 값 0을 분리한다. 조회 실패·최초 조회를 `0 → 현재 값` 증가로 만들지 않는다.
- 공개 식별자가 없으면 만들어내지 않는다. 비밀 값은 키나 비교 대상으로 저장하지 않는다.
- 정상 시도는 `pending → confirmed_self → consumed` 또는 `pending → expired_unknown`으로 끝난다. 비차단 결과/타인의 다른 결과가 모든 시도를 종료시키지 않는다.
- 적 중단 → 내 시전 이벤트, 미터 갱신 → 적 중단 등 역순도 짧게 버퍼링한다. 대기 시간은 진단으로 결정하며, 대기 중 시간만으로 확정하지 않는다.
- 타이머 콜백은 generation과 attempt ID, 활성 설정을 확인한다. 새 시도·새 전투에 과거 콜백이 작용하면 안 된다.
- target/focus/nameplate의 같은 중단 중복은 공개 cast 식별자 등으로 합친다. 식별 불가능하면 성공한 attempt 소비를 최종 중복 방지로 쓴다.
- 같은 시전의 중복 통지는 합치되, player와 pet의 별개 시도를 임의로 하나로 덮어쓰지 않는다. 안전한 식별자가 없으면 병합/연결 불확실성을 진단한다.
- 신성한 종 다중 적 중단은 하나의 사용에 소리 1회다. 일반 차단과 공유하는 전역 긴 음소거 타이머로 후속 정상 성공을 막지 않는다.
- 대상이 focus/mouseover/소환수 대상일 수 있으므로 현재 target 일치만 강제하지 않는다. 대상 정보를 읽을 수 없다는 이유로 아무 중단이나 연결하지도 않는다.
- 공개 차단자 불일치는 그 결과의 강한 배제 증거다. 그 결과를 메타데이터 추정으로 덮어쓰지 않는다.
- 소환수 GUID는 시도 시점 identity를 보존한다. 소환수 교체 후 과거 pet 결과를 새 pet 시도로 사용하지 않는다.
- 세션 갱신·미터 초기화·로그인·지역 이동·기능 끔·플레이어/소환수 identity 변화 시 관련 시도와 snapshot 연결을 무효화한다. 첫 snapshot은 기준선만 설정한다.
- 전투 종료 직후 지연 증거는 아직 동일 generation·세션·유효 시도임이 확인될 때만 처리한다. 이전 전투 기록을 다음 전투로 넘기지 않는다.
- 세션 identity를 검증할 수 없는 동안에는 공개 GUID 결과 경로만 계속 사용한다.
- 실제 소리 재생은 `SA_PlaySound(MimDiceDB.interruptAlert)` 한 경로로 모은다. 사용자 선택 파일/채널/활성 여부를 그대로 적용한다.

이벤트 통합 시 기존 OnEvent의 다른 분기를 유지한다. 특히 `UNIT_SPELLCAST_SUCCEEDED`에서 차단 처리 결과 때문에 사용자 지정 주문 알림까지 조기 return하지 않는다.

사용자가 차단 주문을 일반 `soundAlerts`에도 직접 등록했다면 그 소리는 시전 알림이다. 차단 성공 소리와 별도로 날 수 있다. 설정을 몰래 삭제하거나 해당 기능의 의미를 바꾸지 말고 테스트에서 구분한다.

## 7. 진단 명세와 실측 절차

진단 기본값은 꺼짐. 팝업·매 이벤트 채팅 출력 금지. 짧은 메모리 ring buffer에 제한된 개수만 저장하고 명령으로 요약한다. 종료하면 이벤트·임시 상태를 정리한다.

안전하게 기록할 내용:

- 클라이언트 build, 장소 유형, 전투 여부, API 사용 가능 여부.
- 이벤트명, 수신 시각, 로컬 revision/generation, 공개인 meterType/sessionID.
- attempt/result의 로컬 ID, source 구분 player/pet, 판정 이유.
- `secret / nil / public / api_error / invalid_structure` 같은 검사 결과.
- 공개값으로 검증된 길이·isLocalPlayer·전후 변화. 비밀 실제 값은 출력하지 않는다.
- 최종 `confirmed_self / confirmed_other / unknown / expired / duplicate`와 소리 횟수.

실측 순서:

1. 야외에서 내 정상 차단과 타인 차단으로 공개 GUID 경로 확인.
2. 일반 던전·쐐기 전투 중 같은 정보를 수집하여 각 table/필드의 실제 접근 가능 여부 확인.
3. 내 첫 차단, 같은 주문 두 번째 차단, 다른 주문 차단을 각각 비교. 배열 길이와 실제 횟수를 혼동하지 않음.
4. 두 사람이 같은 몹에 거의 동시에 차단. 게임 내 서버 기록상 내 횟수가 늘지 않았을 때 소리가 없어야 함.
5. 다른 몹 두 마리를 각자 동시에 차단. 남의 증가 때문에 내 성공을 지우면 안 됨.
6. 흑마법사 소환수, 소환수 교체, 신성한 종 다중 대상, 긴 투사체 도달을 확인.
7. 내 차단기 사용과 당기기/기절/자연 종료를 겹쳐 미터 증거 오염 확인.
8. 전투 종료·새 전투·미터 초기화·던전 안 reload 후 과거 누적분 재생이 없는지 확인.
9. 레이드에서도 별도 확인. 쐐기 실측을 레이드 전체 보장으로 보고하지 않음.

단순 `/dump`로 비밀 숫자가 화면에 보이는 것은 Lua에서 비교 가능하다는 증거가 아니다. `pcall=true`만으로도 A 방식 성공으로 보고하지 않는다.

## 8. 자동 테스트 요구사항

기존 `tests/test_sound_regressions.py`는 실제 Lua 코드를 `lupa.lua51`에 로드하는 테스트다. 현재 기대값 중 오탐을 정답으로 고정한 부분이 있다.

- `interrupt: pet success and secret result`: 증거 없이 secret 결과만 넣어도 두 번째 재생을 기대한다. 새 정책에 맞게 수정.
- `interrupt: protection paladin Divine Toll`: secret 결과만으로 재생을 기대한다. 미확인 무음과 확인 성공 1회를 분리.
- 현재 mock의 `SECRET`는 table이다. 실제 비밀 문자열도 `type==string`일 수 있으므로 mock 통과만으로 검사 순서 안전을 입증하지 않는다. 정적 점검과 게임 오류 확인을 병행한다.
- 현재 `C_Timer.After` mock은 아무것도 하지 않는다. 새 버퍼/타이머 동작을 시험하려면 가짜 clock과 예약 실행 큐를 구현하고, 시각 이동 및 콜백 실행 순서를 통제한다.

필수 사례:

| 입력 상황 | 기대 |
| --- | --- |
| 내 시전만 발생 | 0회 |
| 내 시전 + 공개 내 GUID 결과 | 1회 |
| 내 시전 + 공개 타인 GUID 결과 | 0회 |
| 내 시전 + secret 결과, 추가 증거 없음 | 0회, 만료 unknown |
| 신성한 종 + nil/빈 차단자/타인 차단자 | 0회 |
| 정상 채널 차단 + 검증된 내 증거 | 1회 |
| 신성한 종 여러 적의 검증된 성공 | 사용당 1회 |
| target/focus/nameplate 중복, 미터 중복 갱신 | 같은 시도 1회 |
| 중단→시전, 미터→중단, 같은 프레임 두 차단 | 연결 가능한 내 성공만 1회씩 |
| 내 행 없음/조회 실패/빈 table 첫 조회 | 실패 확정·자동 성공 모두 금지 |
| 공개 횟수 증가 + 유효한 내 시도/결과/세션 | 1회 |
| 숫자 secret·반복 주문으로 길이 그대로 | 시간 추정 재생 금지 |
| 남과 내가 다른 적을 동시에 차단 | 내 증거를 유지하여 내 성공 1회 |
| source identity/세션 변경, 오래된 callback | 과거 증거 재사용 0회 |
| 미터 API/Enum 없음, 오류, 비밀 컨테이너 | 오류 없이 unknown, 다른 알림 정상 |
| 공개 컨테이너에 비밀 자식과 공개 메타데이터 혼재 | 안전한 필드만 읽고 비밀 값은 비교하지 않음 |
| 실패 후 조회 회복, 미터 reset/reload | 누적분 가짜 재생 0회 |
| 기능 끈 뒤 지연 증거 도착 | 0회 |
| 내장/파일/번호 소리 및 저장된 설정 | 기존 선택 보존 |

실행 명령은 현재 환경의 Python/lupa 설치를 확인한 후 사용:

```powershell
python tests/test_sound_regressions.py
python tests/test_settings_ui.py
```

모듈 분리/TOC 변경 등이 있으면 영향받는 기존 테스트도 실행한다. Lua 문법 검사와 `git diff --check`도 실시한다. 실행 불가 항목은 통과했다고 쓰지 않는다.

## 9. 완료 보고에 반드시 포함할 것

- 제거한 오탐 경로와 실제로 채택한 성공 증거 목록.
- 전투 중 A 방식의 공개 숫자 비교가 가능했는지, 메타데이터만 가능했는지, 미확인인지 구분.
- 같은 주문 반복 차단 등 조용히 놓칠 수 있는 조건과 검증하지 못한 직업·장소.
- 자동 테스트 결과와 게임 실측 결과를 분리. 실제 소리를 듣지 않았다면 그렇게 표시.
- 기존 기능·설정 및 사용자 diff 보존 여부.
- 겹짤 감소를 “정확도 100%”로 표현하지 않음. 타이밍 추정을 제거했는지 코드로 확인.

클로드에게 전달할 핵심 지시:

> 1단계의 오탐 제거와 기존 공개 GUID 성공 보존부터 구현하라. 이어 미터 증거 수집과 이벤트 순서·세션·중복 회귀 테스트를 완성하라. 엘스미어의 metadata snapshot 개념과 EXBoss의 시전/성공 분리를 참고하되, `OwnPending → player` 추정 fallback과 위젯 비밀 값 표시를 사운드 성공 조건으로 가져오지 마라. 미터 연결은 현재 클라이언트 실측으로 검증한 증거만 활성화하고, 나머지는 unknown으로 남겨라. 소스와 공개 API의 개념을 참고해 독립 구현하고 타 애드온의 내부 전역/콜백에 의존하지 마라.
