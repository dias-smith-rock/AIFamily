#!/usr/bin/env python3
"""Add / update String Catalog entries for guest-mode UI copy."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
XCSTRINGS_PATH = ROOT / "reminder" / "Localizable.xcstrings"
LOCALES = ["en", "zh-Hans", "zh-Hant", "es", "pt", "ar", "hi", "fr", "ta"]

GUEST_KEYS: dict[str, dict[str, str]] = {
    "我": {
        "en": "Me",
        "zh-Hans": "我",
        "zh-Hant": "我",
        "es": "Yo",
        "pt": "Eu",
        "fr": "Moi",
        "ar": "أنا",
        "hi": "मैं",
        "ta": "நான்",
    },
    "我的空间": {
        "en": "My Space",
        "zh-Hans": "我的空间",
        "zh-Hant": "我的空間",
        "es": "Mi espacio",
        "pt": "Meu espaço",
        "fr": "Mon espace",
        "ar": "مساحتي",
        "hi": "मेरा स्थान",
        "ta": "என் இடம்",
    },
    "暂不登录，先试用": {
        "en": "Try without signing in",
        "zh-Hans": "暂不登录，先试用",
        "zh-Hant": "暫不登入，先試用",
        "es": "Probar sin iniciar sesión",
        "pt": "Experimentar sem entrar",
        "fr": "Essayer sans se connecter",
        "ar": "جرّب دون تسجيل الدخول",
        "hi": "बिना लॉग इन किए आज़माएं",
        "ta": "உள்நுழையாமல் முயற்சிக்கவும்",
    },
    "试用模式": {
        "en": "Trial mode",
        "zh-Hans": "试用模式",
        "zh-Hant": "試用模式",
        "es": "Modo de prueba",
        "pt": "Modo de avaliação",
        "fr": "Mode d'essai",
        "ar": "وضع التجربة",
        "hi": "परीक्षण मोड",
        "ta": "சோதனை பயன்முறை",
    },
    "当前数据仅保存在本机。登录后可同步到云端，并与家人协作。": {
        "en": "Your data is stored on this device only. Sign in to sync to the cloud and collaborate with family.",
        "zh-Hans": "当前数据仅保存在本机。登录后可同步到云端，并与家人协作。",
        "zh-Hant": "目前資料僅儲存在本機。登入後可同步至雲端，並與家人協作。",
        "es": "Los datos solo se guardan en este dispositivo. Inicia sesión para sincronizar en la nube y colaborar con tu familia.",
        "pt": "Os dados ficam apenas neste dispositivo. Faça login para sincronizar na nuvem e colaborar com a família.",
        "fr": "Les données sont stockées uniquement sur cet appareil. Connectez-vous pour les synchroniser dans le cloud et collaborer en famille.",
        "ar": "البيانات محفوظة على هذا الجهاز فقط. سجّل الدخول للمزامنة مع السحابة والتعاون مع العائلة.",
        "hi": "डेटा केवल इस डिवाइस पर है। क्लाउड में सिंक और परिवार के साथ सहयोग के लिए लॉग इन करें।",
        "ta": "தரவு இந்த சாதனத்தில் மட்டுமே சேமிக்கப்படுகிறது. கிளவுடில் ஒத்திசைக்கவும் குடும்பத்துடன் இணைந்து பணியாற்ற உள்நுழையவும்.",
    },
    "使用 Google 同步": {
        "en": "Sync with Google",
        "zh-Hans": "使用 Google 同步",
        "zh-Hant": "使用 Google 同步",
        "es": "Sincronizar con Google",
        "pt": "Sincronizar com o Google",
        "fr": "Synchroniser avec Google",
        "ar": "المزامنة عبر Google",
        "hi": "Google से सिंक करें",
        "ta": "Google மூலம் ஒத்திசைக்கவும்",
    },
    "通过 Apple 同步": {
        "en": "Sync with Apple",
        "zh-Hans": "通过 Apple 同步",
        "zh-Hant": "透過 Apple 同步",
        "es": "Sincronizar con Apple",
        "pt": "Sincronizar com a Apple",
        "fr": "Synchroniser avec Apple",
        "ar": "المزامنة عبر Apple",
        "hi": "Apple से सिंक करें",
        "ta": "Apple மூலம் ஒத்திசைக்கவும்",
    },
    "放弃本地数据": {
        "en": "Discard local data",
        "zh-Hans": "放弃本地数据",
        "zh-Hant": "放棄本機資料",
        "es": "Descartar datos locales",
        "pt": "Descartar dados locais",
        "fr": "Supprimer les données locales",
        "ar": "تجاهل البيانات المحلية",
        "hi": "स्थानीय डेटा छोड़ें",
        "ta": "உள்ளூர் தரவை நிராகரிக்கவும்",
    },
    "将删除本机试用数据，且无法恢复。": {
        "en": "Trial data on this device will be deleted and cannot be recovered.",
        "zh-Hans": "将删除本机试用数据，且无法恢复。",
        "zh-Hant": "將刪除本機試用資料，且無法復原。",
        "es": "Se eliminarán los datos de prueba del dispositivo y no se podrán recuperar.",
        "pt": "Os dados de avaliação neste dispositivo serão excluídos e não poderão ser recuperados.",
        "fr": "Les données d'essai sur cet appareil seront supprimées sans possibilité de restauration.",
        "ar": "سيتم حذف بيانات التجربة على هذا الجهاز ولا يمكن استعادتها.",
        "hi": "इस डिवाइस का परीक्षण डेटा हटा दिया जाएगा और पुनर्प्राप्त नहीं किया जा सकता।",
        "ta": "இந்த சாதனத்தின் சோதனை தரவு நீக்கப்படும்; மீட்டெடுக்க முடியாது.",
    },
    "本地数据尚未同步": {
        "en": "Local data not synced yet",
        "zh-Hans": "本地数据尚未同步",
        "zh-Hant": "本機資料尚未同步",
        "es": "Datos locales aún no sincronizados",
        "pt": "Dados locais ainda não sincronizados",
        "fr": "Données locales pas encore synchronisées",
        "ar": "لم تتم مزامنة البيانات المحلية بعد",
        "hi": "स्थानीय डेटा अभी सिंक नहीं हुआ",
        "ta": "உள்ளூர் தரவு இன்னும் ஒத்திசைக்கப்படவில்லை",
    },
    "轻点重试，将试用数据写入云端。": {
        "en": "Tap to retry and upload trial data to the cloud.",
        "zh-Hans": "轻点重试，将试用数据写入云端。",
        "zh-Hant": "輕點重試，將試用資料寫入雲端。",
        "es": "Toca para reintentar y subir los datos de prueba a la nube.",
        "pt": "Toque para tentar novamente e enviar os dados de avaliação para a nuvem.",
        "fr": "Appuyez pour réessayer et envoyer les données d'essai vers le cloud.",
        "ar": "اضغط لإعادة المحاولة ورفع بيانات التجربة إلى السحابة.",
        "hi": "पुनः प्रयास करें और परीक्षण डेटा क्लाउड पर अपलोड करें।",
        "ta": "மீண்டும் முயற்சிக்க தட்டவும்; சோதனை தரவை கிளவுடில் பதிவேற்றவும்.",
    },
    "试用用户": {
        "en": "Trial user",
        "zh-Hans": "试用用户",
        "zh-Hant": "試用用戶",
        "es": "Usuario de prueba",
        "pt": "Usuário de avaliação",
        "fr": "Utilisateur d'essai",
        "ar": "مستخدم تجريبي",
        "hi": "परीक्षण उपयोगकर्ता",
        "ta": "சோதனை பயனர்",
    },
    "数据仅保存在本机": {
        "en": "Data stored on this device only",
        "zh-Hans": "数据仅保存在本机",
        "zh-Hant": "資料僅儲存在本機",
        "es": "Los datos solo se guardan en este dispositivo",
        "pt": "Dados armazenados apenas neste dispositivo",
        "fr": "Données stockées uniquement sur cet appareil",
        "ar": "البيانات محفوظة على هذا الجهاز فقط",
        "hi": "डेटा केवल इस डिवाइस पर सहेजा गया",
        "ta": "தரவு இந்த சாதனத்தில் மட்டுமே சேமிக்கப்படுகிறது",
    },
    "本地数据已同步到云端": {
        "en": "Local data synced to the cloud",
        "zh-Hans": "本地数据已同步到云端",
        "zh-Hant": "本機資料已同步至雲端",
        "es": "Datos locales sincronizados con la nube",
        "pt": "Dados locais sincronizados na nuvem",
        "fr": "Données locales synchronisées dans le cloud",
        "ar": "تمت مزامنة البيانات المحلية مع السحابة",
        "hi": "स्थानीय डेटा क्लाउड में सिंक हो गया",
        "ta": "உள்ளூர் தரவு கிளவுடில் ஒத்திசைக்கப்பட்டது",
    },
    "退出试用": {
        "en": "Exit trial",
        "zh-Hans": "退出试用",
        "zh-Hant": "退出試用",
        "es": "Salir del modo de prueba",
        "pt": "Sair da avaliação",
        "fr": "Quitter l'essai",
        "ar": "إنهاء التجربة",
        "hi": "परीक्षण से बाहर निकलें",
        "ta": "சோதனையிலிருந்து வெளியேறு",
    },
    "需要登录": {
        "en": "Sign-in required",
        "zh-Hans": "需要登录",
        "zh-Hant": "需要登入",
        "es": "Se requiere iniciar sesión",
        "pt": "É necessário fazer login",
        "fr": "Connexion requise",
        "ar": "يلزم تسجيل الدخول",
        "hi": "लॉग इन आवश्यक है",
        "ta": "உள்நுழைவு தேவை",
    },
    "登录后可使用云端功能，并同步本地数据。": {
        "en": "Sign in to use cloud features and sync your local data.",
        "zh-Hans": "登录后可使用云端功能，并同步本地数据。",
        "zh-Hant": "登入後可使用雲端功能，並同步本機資料。",
        "es": "Inicia sesión para usar funciones en la nube y sincronizar tus datos locales.",
        "pt": "Faça login para usar recursos na nuvem e sincronizar dados locais.",
        "fr": "Connectez-vous pour utiliser les fonctions cloud et synchroniser vos données locales.",
        "ar": "سجّل الدخول لاستخدام ميزات السحابة ومزامنة بياناتك المحلية.",
        "hi": "क्लाउड सुविधाओं और स्थानीय डेटा सिंक के लिए लॉग इन करें।",
        "ta": "கிளவுட் அம்சங்களையும் உள்ளூர் தரவை ஒத்திசைக்கவும் உள்நுழையவும்.",
    },
    "登录后可使用此功能，并同步本地数据。": {
        "en": "Sign in to use this feature and sync your local data.",
        "zh-Hans": "登录后可使用此功能，并同步本地数据。",
        "zh-Hant": "登入後可使用此功能，並同步本機資料。",
        "es": "Inicia sesión para usar esta función y sincronizar tus datos locales.",
        "pt": "Faça login para usar este recurso e sincronizar dados locais.",
        "fr": "Connectez-vous pour utiliser cette fonction et synchroniser vos données locales.",
        "ar": "سجّل الدخول لاستخدام هذه الميزة ومزامنة بياناتك المحلية.",
        "hi": "इस सुविधा और स्थानीय डेटा सिंक के लिए लॉग इन करें।",
        "ta": "இந்த அம்சத்தையும் உள்ளூர் தரவை ஒத்திசைக்கவும் உள்நுழையவும்.",
    },
    "登录后可使用拍照识图功能。": {
        "en": "Sign in to use photo recognition for tasks.",
        "zh-Hans": "登录后可使用拍照识图功能。",
        "zh-Hant": "登入後可使用拍照識圖功能。",
        "es": "Inicia sesión para usar el reconocimiento de fotos en tareas.",
        "pt": "Faça login para usar reconhecimento de fotos em tarefas.",
        "fr": "Connectez-vous pour utiliser la reconnaissance photo pour les tâches.",
        "ar": "سجّل الدخول لاستخدام التعرف على الصور في المهام.",
        "hi": "कार्यों में फोटो पहचान के लिए लॉग इन करें।",
        "ta": "பணிகளில் புகைப்பட அடையாளத்திற்கு உள்நுழையவும்.",
    },
    "登录后可与群组成员共享实时位置。": {
        "en": "Sign in to share live location with group members.",
        "zh-Hans": "登录后可与群组成员共享实时位置。",
        "zh-Hant": "登入後可與群組成員共享即時位置。",
        "es": "Inicia sesión para compartir ubicación en tiempo real con el grupo.",
        "pt": "Faça login para compartilhar localização ao vivo com o grupo.",
        "fr": "Connectez-vous pour partager votre position en direct avec le groupe.",
        "ar": "سجّل الدخول لمشاركة الموقع المباشر مع أعضاء المجموعة.",
        "hi": "समूह सदस्यों के साथ लाइव स्थान साझा करने के लिए लॉग इन करें।",
        "ta": "குழு உறுப்பினர்களுடன் நேரடி இருப்பிடத்தைப் பகிர உள்நுழையவும்.",
    },
    "迁移后未能获取群组成员身份，请稍后重试。": {
        "en": "Could not load membership after migration. Please try again later.",
        "zh-Hans": "迁移后未能获取群组成员身份，请稍后重试。",
        "zh-Hant": "遷移後未能取得群組成員身分，請稍後重試。",
        "es": "No se pudo obtener la membresía tras la migración. Inténtalo más tarde.",
        "pt": "Não foi possível obter a associação após a migração. Tente novamente mais tarde.",
        "fr": "Impossible d'obtenir l'appartenance au groupe après la migration. Réessayez plus tard.",
        "ar": "تعذّر الحصول على عضوية المجموعة بعد الترحيل. حاول لاحقًا.",
        "hi": "माइग्रेशन के बाद सदस्यता प्राप्त नहीं हो सकी। बाद में पुनः प्रयास करें।",
        "ta": "இடமாற்றத்திற்குப் பிறகு உறுப்பினர் அடையாளம் கிடைக்கவில்லை. பின்னர் முயற்சிக்கவும்.",
    },
    "创建云端群组失败，请检查网络后重试。": {
        "en": "Failed to create cloud group. Check your network and try again.",
        "zh-Hans": "创建云端群组失败，请检查网络后重试。",
        "zh-Hant": "建立雲端群組失敗，請檢查網路後重試。",
        "es": "No se pudo crear el grupo en la nube. Comprueba la red e inténtalo de nuevo.",
        "pt": "Falha ao criar grupo na nuvem. Verifique a rede e tente novamente.",
        "fr": "Échec de la création du groupe cloud. Vérifiez le réseau et réessayez.",
        "ar": "فشل إنشاء مجموعة السحابة. تحقق من الشبكة وأعد المحاولة.",
        "hi": "क्लाउड समूह बनाना विफल। नेटवर्क जाँचें और पुनः प्रयास करें।",
        "ta": "கிளவுட் குழுவை உருவாக்க முடியவில்லை. நெட்வொர்க்கைச் சரிபார்த்து மீண்டும் முயற்சிக்கவும்.",
    },
}


def make_unit(value: str) -> dict:
    return {"stringUnit": {"state": "translated", "value": value}}


def make_entry(translations: dict[str, str]) -> dict:
    return {"localizations": {locale: make_unit(translations[locale]) for locale in LOCALES}}


def main() -> None:
    data = json.loads(XCSTRINGS_PATH.read_text(encoding="utf-8"))
    strings = data["strings"]
    for key, translations in GUEST_KEYS.items():
        strings[key] = make_entry(translations)
    XCSTRINGS_PATH.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Updated {len(GUEST_KEYS)} guest keys in {XCSTRINGS_PATH}")


if __name__ == "__main__":
    main()
