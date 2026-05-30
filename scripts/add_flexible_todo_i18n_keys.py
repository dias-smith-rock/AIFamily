#!/usr/bin/env python3
"""Fill String Catalog entries for flexible todo / dual-form task UI."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
XCSTRINGS_PATH = ROOT / "reminder" / "Localizable.xcstrings"
LOCALES = ["en", "zh-Hans", "zh-Hant", "es", "pt", "ar", "hi", "fr", "ta"]

TRANSLATIONS: dict[str, dict[str, str]] = {
    "%@前": {
        "en": "Due by %@",
        "zh-Hans": "%@前",
        "zh-Hant": "%@前",
        "es": "Para el %@",
        "pt": "Até %@",
        "fr": "Avant le %@",
        "ar": "قبل %@",
        "hi": "%@ तक",
        "ta": "%@க்கு முன்",
    },
    "添加没有具体开始时间的任务，在截止日前完成即可。": {
        "en": "Add tasks without a set start time—complete them before the due date.",
        "zh-Hans": "添加没有具体开始时间的任务，在截止日前完成即可。",
        "zh-Hant": "新增沒有具體開始時間的任務，在截止日前完成即可。",
        "es": "Añade tareas sin hora de inicio; complétalas antes de la fecha límite.",
        "pt": "Adicione tarefas sem horário de início—conclua-as antes do prazo.",
        "fr": "Ajoutez des tâches sans heure de début—à terminer avant la date limite.",
        "ar": "أضِف مهامًا بلا وقت بدء محدد—أنجزها قبل الموعد النهائي.",
        "hi": "बिना शुरुआती समय के कार्य जोड़ें—अंतिम तिथि से पहले पूरा करें।",
        "ta": "தொடக்க நேரம் இல்லாத பணிகளைச் சேர்க்கவும்—காலக்கெடுவுக்கு முன் முடிக்கவும்.",
    },
    "在此之前任意时间完成即可": {
        "en": "Can be completed anytime before this date.",
        "zh-Hans": "在此之前任意时间完成即可",
        "zh-Hant": "在此之前任意時間完成即可",
        "es": "Puede completarse en cualquier momento antes de esta fecha.",
        "pt": "Pode ser concluída a qualquer momento antes desta data.",
        "fr": "Peut être terminée à tout moment avant cette date.",
        "ar": "يمكن إنجازها في أي وقت قبل هذا الموعد.",
        "hi": "इस तिथि से पहले कभी भी पूरा किया जा सकता है।",
        "ta": "இந்த தேதிக்கு முன் எப்போது வேண்டுமானாலும் முடிக்கலாம்.",
    },
    "在这之前完成": {
        "en": "Complete before",
        "zh-Hans": "在这之前完成",
        "zh-Hant": "在這之前完成",
        "es": "Completar antes de",
        "pt": "Concluir antes de",
        "fr": "À terminer avant le",
        "ar": "أنجِز قبل",
        "hi": "इससे पहले पूरा करें",
        "ta": "இதற்கு முன் முடிக்கவும்",
    },
    "今天截止": {
        "en": "Due today",
        "zh-Hans": "今天截止",
        "zh-Hant": "今天截止",
        "es": "Vence hoy",
        "pt": "Vence hoje",
        "fr": "À faire aujourd'hui",
        "ar": "مستحق اليوم",
        "hi": "आज तक",
        "ta": "இன்று காலக்கெடு",
    },
    "以后": {
        "en": "Later",
        "zh-Hans": "以后",
        "zh-Hant": "以後",
        "es": "Más adelante",
        "pt": "Mais tarde",
        "fr": "Plus tard",
        "ar": "لاحقًا",
        "hi": "बाद में",
        "ta": "பின்னர்",
    },
    "已逾期": {
        "en": "Overdue",
        "zh-Hans": "已逾期",
        "zh-Hant": "已逾期",
        "es": "Vencido",
        "pt": "Atrasado",
        "fr": "En retard",
        "ar": "متأخر",
        "hi": "अतिदेय",
        "ta": "காலாவதியானது",
    },
    "待办": {
        "en": "To-Dos",
        "zh-Hans": "待办",
        "zh-Hant": "待辦",
        "es": "Pendientes",
        "pt": "A fazer",
        "fr": "À faire",
        "ar": "المهام",
        "hi": "करने योग्य",
        "ta": "செய்ய வேண்டியவை",
    },
    "截止日期": {
        "en": "Due date",
        "zh-Hans": "截止日期",
        "zh-Hant": "截止日期",
        "es": "Fecha límite",
        "pt": "Data limite",
        "fr": "Date limite",
        "ar": "تاريخ الاستحقاق",
        "hi": "अंतिम तिथि",
        "ta": "காலக்கெடு தேதி",
    },
    "截止期限": {
        "en": "Due by",
        "zh-Hans": "截止期限",
        "zh-Hant": "截止期限",
        "es": "Fecha límite",
        "pt": "Prazo",
        "fr": "Date limite",
        "ar": "الموعد النهائي",
        "hi": "अंतिम समय",
        "ta": "காலக்கெடு",
    },
    "新建待办": {
        "en": "New To-Do",
        "zh-Hans": "新建待办",
        "zh-Hant": "新建待辦",
        "es": "Nueva tarea",
        "pt": "Nova tarefa",
        "fr": "Nouvelle tâche",
        "ar": "مهمة جديدة",
        "hi": "नया कार्य",
        "ta": "புதிய பணி",
    },
    "新建日程": {
        "en": "New Event",
        "zh-Hans": "新建日程",
        "zh-Hant": "新建日程",
        "es": "Nuevo evento",
        "pt": "Novo evento",
        "fr": "Nouvel événement",
        "ar": "موعد جديد",
        "hi": "नया कार्यक्रम",
        "ta": "புதிய நிகழ்வு",
    },
    "编辑待办": {
        "en": "Edit To-Do",
        "zh-Hans": "编辑待办",
        "zh-Hant": "編輯待辦",
        "es": "Editar tarea",
        "pt": "Editar tarefa",
        "fr": "Modifier la tâche",
        "ar": "تعديل المهمة",
        "hi": "कार्य संपादित करें",
        "ta": "பணியைத் திருத்து",
    },
    "编辑日程": {
        "en": "Edit Event",
        "zh-Hans": "编辑日程",
        "zh-Hant": "編輯日程",
        "es": "Editar evento",
        "pt": "Editar evento",
        "fr": "Modifier l'événement",
        "ar": "تعديل الموعد",
        "hi": "कार्यक्रम संपादित करें",
        "ta": "நிகழ்வைத் திருத்து",
    },
    "暂无待办": {
        "en": "No to-dos yet",
        "zh-Hans": "暂无待办",
        "zh-Hant": "暫無待辦",
        "es": "Aún no hay tareas pendientes",
        "pt": "Nenhuma tarefa pendente",
        "fr": "Aucune tâche pour l'instant",
        "ar": "لا توجد مهام بعد",
        "hi": "अभी कोई कार्य नहीं",
        "ta": "இன்னும் பணிகள் இல்லை",
    },
    "未设截止日": {
        "en": "No due date",
        "zh-Hans": "未设截止日",
        "zh-Hant": "未設截止日",
        "es": "Sin fecha límite",
        "pt": "Sem prazo definido",
        "fr": "Aucune date limite",
        "ar": "لم يُحدد موعد نهائي",
        "hi": "कोई अंतिम तिथि नहीं",
        "ta": "காலக்கெடு இல்லை",
    },
    "本周截止": {
        "en": "Due this week",
        "zh-Hans": "本周截止",
        "zh-Hant": "本週截止",
        "es": "Vence esta semana",
        "pt": "Vence esta semana",
        "fr": "Cette semaine",
        "ar": "مستحق هذا الأسبوع",
        "hi": "इस सप्ताह तक",
        "ta": "இந்த வாரம் காலக்கெடு",
    },
    "灵活待办不支持批量更新重复任务。": {
        "en": "Flexible to-dos can't be batch-updated as a recurring series.",
        "zh-Hans": "灵活待办不支持批量更新重复任务。",
        "zh-Hant": "靈活待辦不支援批量更新重複任務。",
        "es": "Las tareas flexibles no admiten actualización masiva de series recurrentes.",
        "pt": "Tarefas flexíveis não suportam atualização em lote de séries recorrentes.",
        "fr": "Les tâches flexibles ne prennent pas en charge la mise à jour groupée des séries récurrentes.",
        "ar": "المهام المرنة لا تدعم التحديث الجماعي للسلسلة المتكررة.",
        "hi": "लचीले कार्य आवर्ती श्रृंखला का बैच अपडेट समर्थित नहीं करते।",
        "ta": "நெகிழ்வான பணிகள் தொடர் பணிகளை மொத்தமாகப் புதுப்பிக்க முடியாது.",
    },
    "灵活待办不支持重复规则。": {
        "en": "Flexible to-dos don't support recurrence.",
        "zh-Hans": "灵活待办不支持重复规则。",
        "zh-Hant": "靈活待辦不支援重複規則。",
        "es": "Las tareas flexibles no admiten repetición.",
        "pt": "Tarefas flexíveis não suportam repetição.",
        "fr": "Les tâches flexibles ne prennent pas en charge la récurrence.",
        "ar": "المهام المرنة لا تدعم التكرار.",
        "hi": "लचीले कार्य पुनरावृत्ति का समर्थन नहीं करते।",
        "ta": "நெகிழ்வான பணிகள் மீண்டும் வருதலை ஆதரிக்காது.",
    },
    "已逾期 %lld": {
        "en": "%lld overdue",
        "zh-Hans": "已逾期 %lld",
        "zh-Hant": "已逾期 %lld",
        "es": "%lld vencidas",
        "pt": "%lld atrasadas",
        "fr": "%lld en retard",
        "ar": "%lld متأخرة",
        "hi": "%lld अतिदेय",
        "ta": "%lld காலாவதி",
    },
    "查看已逾期任务": {
        "en": "View overdue tasks",
        "zh-Hans": "查看已逾期任务",
        "zh-Hant": "查看已逾期任務",
        "es": "Ver tareas vencidas",
        "pt": "Ver tarefas atrasadas",
        "fr": "Voir les tâches en retard",
        "ar": "عرض المهام المتأخرة",
        "hi": "अतिदेय कार्य देखें",
        "ta": "காலாவதியான பணிகளைக் காண்க",
    },
    "暂无即将到期": {
        "en": "Nothing due soon",
        "zh-Hans": "暂无即将到期",
        "zh-Hant": "暫無即將到期",
        "es": "Nada próximo a vencer",
        "pt": "Nada a vencer em breve",
        "fr": "Rien à échéance proche",
        "ar": "لا شيء مستحق قريبًا",
        "hi": "जल्द कोई अंतिम तिथि नहीं",
        "ta": "விரைவில் காலக்கெடு இல்லை",
    },
    "当前待办均已逾期，请从右上角入口查看。": {
        "en": "All open to-dos are overdue. Tap the button at the top right to review them.",
        "zh-Hans": "当前待办均已逾期，请从右上角入口查看。",
        "zh-Hant": "目前待辦均已逾期，請從右上角入口查看。",
        "es": "Todas las tareas pendientes están vencidas. Tócalas arriba a la derecha para revisarlas.",
        "pt": "Todas as tarefas estão atrasadas. Toque no botão no canto superior direito.",
        "fr": "Toutes les tâches sont en retard. Appuyez en haut à droite pour les voir.",
        "ar": "جميع المهام متأخرة. اضغط الزر أعلى اليمين للعرض.",
        "hi": "सभी कार्य अतिदेय हैं। ऊपर दाएँ बटन से देखें।",
        "ta": "அனைத்து பணிகளும் காலாவதியாகியுள்ளன. மேல் வலதில் உள்ள பொத்தானைத் தட்டவும்.",
    },
    "%lld 个待办已过期": {
        "en": "%lld to-do(s) overdue",
        "zh-Hans": "%lld 个待办已过期",
        "zh-Hant": "%lld 個待辦已過期",
        "es": "%lld tareas vencidas",
        "pt": "%lld tarefas atrasadas",
        "fr": "%lld tâche(s) en retard",
        "ar": "%lld مهام متأخرة",
        "hi": "%lld कार्य अतिदेय",
        "ta": "%lld பணிகள் காலாவதி",
    },
    "点击查看并调整时间": {
        "en": "Tap to review and adjust deadlines",
        "zh-Hans": "点击查看并调整时间",
        "zh-Hant": "點擊查看並調整時間",
        "es": "Toca para revisar y ajustar fechas",
        "pt": "Toque para revisar e ajustar prazos",
        "fr": "Appuyez pour voir et ajuster les échéances",
        "ar": "اضغط للعرض وتعديل المواعيد",
        "hi": "देखने और समय बदलने के लिए टैप करें",
        "ta": "பார்க்கவும் நேரத்தை மாற்றவும் தட்டவும்",
    },
    "当前待办均已逾期，请点击上方横幅查看。": {
        "en": "All open to-dos are overdue. Tap the banner above to review them.",
        "zh-Hans": "当前待办均已逾期，请点击上方横幅查看。",
        "zh-Hant": "目前待辦均已逾期，請點擊上方橫幅查看。",
        "es": "Todas las tareas están vencidas. Toca el banner de arriba para revisarlas.",
        "pt": "Todas as tarefas estão atrasadas. Toque no banner acima para revisar.",
        "fr": "Toutes les tâches sont en retard. Appuyez sur la bannière ci-dessus.",
        "ar": "جميع المهام متأخرة. اضغط الشريط أعلاه للعرض.",
        "hi": "सभी कार्य अतिदेय हैं। ऊपर बैनर पर टैप करें।",
        "ta": "அனைத்து பணிகளும் காலாவதியாகியுள்ளன. மேலுள்ள பேனரைத் தட்டவும்.",
    },
}


def make_localizations(translations: dict[str, str]) -> dict:
    return {
        locale: {
            "stringUnit": {
                "state": "translated",
                "value": translations[locale],
            }
        }
        for locale in LOCALES
    }


def main() -> None:
    data = json.loads(XCSTRINGS_PATH.read_text(encoding="utf-8"))
    strings = data.setdefault("strings", {})

    for key, translations in TRANSLATIONS.items():
        entry = strings.setdefault(key, {})
        entry["localizations"] = make_localizations(translations)

    XCSTRINGS_PATH.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Updated {len(TRANSLATIONS)} keys in {XCSTRINGS_PATH}")


if __name__ == "__main__":
    main()
