"use client";

import { createContext, useContext, useEffect, useMemo, useState } from 'react';

import { de } from './de';
import { el } from './el';
import { en } from './en';
import { id } from './id';
import { ja } from './ja';
import { ko } from './ko';
import { ru } from './ru';
import { tr } from './tr';
import { uk } from './uk';
import { zh } from './zh';
import { pl } from "./pl";
import { zhHant } from './zh-Hant';

export type Language = "en" | "zh" | "ru" | "tr" | "ko" | "de" | "el" | "uk" | "ja" | "zh-Hant" | "id" | "pl";
export type Translations = typeof en;

const SUPPORTED_LANGUAGES: readonly Language[] = [
  "en",
  "zh",
  "ru",
  "tr",
  "ko",
  "de",
  "el",
  "uk",
  "ja",
  "zh-Hant",
  "id",
  "pl",
];

function isLanguage(value: string): value is Language {
  return (SUPPORTED_LANGUAGES as readonly string[]).includes(value);
}

function defaultLanguageFromBrowser(browserLangRaw: string): Language {
  const browserLang = browserLangRaw.toLowerCase();
  const languageMap: Record<string, Language | ((lang: string) => Language)> = {
    zh: (lang) => (lang.includes("hant") ? "zh-Hant" : "zh"),
    pl: "pl",
    ru: "ru",
    tr: "tr",
    ko: "ko",
    de: "de",
    el: "el",
    uk: "uk",
    ja: "ja",
    id: "id",
  };

  const prefix = Object.keys(languageMap).find((p) => browserLang.startsWith(p));
  if (!prefix) return "en";

  const mapping = languageMap[prefix];
  return typeof mapping === "function" ? mapping(browserLang) : mapping;
}

const TRANSLATIONS_BY_LANGUAGE: Record<Language, Translations> = {
  en,
  zh,
  ru,
  tr,
  ko,
  de,
  el,
  uk,
  ja,
  "zh-Hant": zhHant,
  pl,
  id,
};

interface I18nContextType {
  language: Language;
  t: Translations;
  setLanguage: (lang: Language) => void;
}

const I18nContext = createContext<I18nContextType | null>(null);

export function I18nProvider({ children }: { children: React.ReactNode }) {
  const [language, setLanguage] = useState<Language>("en");
  const translations = useMemo(() => {
    return TRANSLATIONS_BY_LANGUAGE[language] ?? en;
  }, [language]);

  useEffect(() => {
    // 从本地存储中获取语言偏好
    const stored = localStorage.getItem("language");
    const desiredLanguage = stored && isLanguage(stored)
      ? stored
      : defaultLanguageFromBrowser(navigator.language);

    // eslint-disable-next-line react-hooks/set-state-in-effect
    setLanguage(desiredLanguage);
  }, []);

  useEffect(() => {
    // 保存语言偏好到本地存储
    localStorage.setItem("language", language);
  }, [language]);

  return (
    <I18nContext.Provider value={{ language, t: translations, setLanguage }}>
      {children}
    </I18nContext.Provider>
  );
}

export function useI18n() {
  const context = useContext(I18nContext);
  if (!context) {
    throw new Error("useI18n must be used within an I18nProvider");
  }
  return context;
}
