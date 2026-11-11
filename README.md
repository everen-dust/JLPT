# JLPT Android MVP

Flutter 기반 Android 일본어 단어 학습 앱의 소스 코드입니다.

## 구현된 기능
- 미니멀 홈, 단어 학습, 양방향 시험, 복습, 통계 화면
- 한자 / 후리가나 / 뜻 / 품사 / 예문
- `flutter_tts`를 이용한 일본어 발음 재생
- SQLite 로컬 데이터 저장
- 오답 횟수와 정답 횟수 기록
- 정답/오답에 따른 간격 반복 일정
- 동작 확인용 N4 예시 단어 20개

## Android 프로젝트 생성 및 실행
이 압축 파일은 앱 소스와 의존성 설정을 담은 스타터 프로젝트입니다. Android Gradle Wrapper 등 Flutter 플랫폼 생성 파일은 포함하지 않았습니다.

1. Flutter stable 및 Android SDK를 설치합니다.
2. 압축을 푼 폴더와 같은 위치에서 Android 프로젝트 뼈대를 생성합니다.

```bash
flutter create --platforms=android --project-name=jlpt jlpt_android_shell
```

3. 이 프로젝트의 `lib/main.dart`와 `pubspec.yaml`을 새로 생성된 `jlpt_android_shell` 폴더에 복사해 기존 파일을 덮어씁니다.
4. 해당 폴더에서 실행합니다.

```bash
cd jlpt_android_shell
flutter pub get
flutter run
```

## APK 빌드
```bash
flutter build apk --release
```
APK 생성 위치: `build/app/outputs/flutter-apk/app-release.apk`

## 유의 사항
- 이 실행 환경에는 Flutter 및 Android SDK가 없어 APK를 직접 빌드하지 못했습니다.
- 기본 단어 20개는 기능 확인용 샘플입니다. 정식 JLPT N4 전체 어휘 목록은 출처와 급수 적합성을 검수해 추가해야 합니다.
- 발음 재생은 Android 기기에 일본어 TTS 음성이 설치되어 있어야 정상 작동합니다.
- 복습 간격은 초기 규칙(오답 10분, 정답 후 1일·3일·7일·14일)으로 구현했습니다.

## GitHub Actions로 APK 빌드하기 (로컬 Flutter 설치 없이)
1. 이 프로젝트 폴더의 파일을 GitHub 저장소에 업로드합니다.
2. 저장소의 **Actions** 탭에서 `Build JLPT Android APK`를 선택합니다.
3. **Run workflow**를 실행하거나 `main` 브랜치에 push하면 빌드가 시작됩니다.
4. 작업이 성공하면 해당 실행 기록 아래 **Artifacts**에서 `JLPT-release-apk`를 내려받습니다.
5. 압축을 풀면 `app-release.apk`가 있습니다.

GitHub 계정과 저장소 업로드 작업은 사용자가 직접 진행해야 합니다. 이 실행 환경에서는 GitHub에 대신 업로드하거나 원격 빌드를 실행할 권한이 없습니다.
