"use client";

import {
  type ButtonHTMLAttributes,
  type InputHTMLAttributes,
  type ReactNode,
  type TextareaHTMLAttributes,
  useEffect,
} from "react";
import styles from "./ui.module.css";

type Variant = "primary" | "secondary" | "ghost" | "destructive";

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: Variant;
  fullWidth?: boolean;
  loading?: boolean;
}

export function Button({
  variant = "primary",
  fullWidth,
  loading,
  disabled,
  className,
  children,
  ...props
}: ButtonProps) {
  const classes = [
    styles.button,
    styles[`button_${variant}`],
    fullWidth ? styles.fullWidth : "",
    loading ? styles.loading : "",
    className ?? "",
  ]
    .filter(Boolean)
    .join(" ");

  return (
    <button className={classes} disabled={disabled || loading} {...props}>
      {loading ? <Spinner size="sm" /> : null}
      <span>{children}</span>
    </button>
  );
}

export function IconButton({
  label,
  className,
  children,
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & { label: string }) {
  return (
    <button
      type="button"
      aria-label={label}
      className={[styles.iconButton, className ?? ""].filter(Boolean).join(" ")}
      {...props}
    >
      {children}
    </button>
  );
}

export function Input({
  className,
  label,
  ...props
}: InputHTMLAttributes<HTMLInputElement> & { label?: string }) {
  const input = (
    <input
      className={[styles.input, className ?? ""].filter(Boolean).join(" ")}
      {...props}
    />
  );
  if (!label) return input;
  return (
    <label className={styles.field}>
      <span className={styles.fieldLabel}>{label}</span>
      {input}
    </label>
  );
}

export function TextArea({
  className,
  label,
  ...props
}: TextareaHTMLAttributes<HTMLTextAreaElement> & { label?: string }) {
  const area = (
    <textarea
      className={[styles.textarea, className ?? ""].filter(Boolean).join(" ")}
      {...props}
    />
  );
  if (!label) return area;
  return (
    <label className={styles.field}>
      <span className={styles.fieldLabel}>{label}</span>
      {area}
    </label>
  );
}

export function Card({
  children,
  className,
  padding = "md",
}: {
  children: ReactNode;
  className?: string;
  padding?: "sm" | "md" | "lg";
}) {
  return (
    <div
      className={[
        styles.card,
        styles[`card_${padding}`],
        className ?? "",
      ]
        .filter(Boolean)
        .join(" ")}
    >
      {children}
    </div>
  );
}

export function Segmented<T extends string>({
  options,
  value,
  onChange,
}: {
  options: { value: T; label: string }[];
  value: T;
  onChange: (value: T) => void;
}) {
  return (
    <div className={styles.segmented} role="tablist">
      {options.map((option) => {
        const active = option.value === value;
        return (
          <button
            key={option.value}
            type="button"
            role="tab"
            aria-selected={active}
            className={[styles.segment, active ? styles.segmentActive : ""]
              .filter(Boolean)
              .join(" ")}
            onClick={() => onChange(option.value)}
          >
            {option.label}
          </button>
        );
      })}
    </div>
  );
}

export function Empty({
  title,
  description,
  action,
}: {
  title: string;
  description?: string;
  action?: ReactNode;
}) {
  return (
    <div className={styles.empty}>
      <p className={styles.emptyTitle}>{title}</p>
      {description ? <p className={styles.emptyDescription}>{description}</p> : null}
      {action}
    </div>
  );
}

export function Spinner({ size = "md" }: { size?: "sm" | "md" | "lg" }) {
  return (
    <span
      className={[styles.spinner, styles[`spinner_${size}`]].join(" ")}
      aria-hidden
    />
  );
}

export function Sheet({
  open,
  onClose,
  title,
  children,
}: {
  open: boolean;
  onClose: () => void;
  title?: string;
  children: ReactNode;
}) {
  useEffect(() => {
    if (!open) return;
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") onClose();
    };
    document.addEventListener("keydown", onKey);
    document.body.style.overflow = "hidden";
    return () => {
      document.removeEventListener("keydown", onKey);
      document.body.style.overflow = "";
    };
  }, [open, onClose]);

  if (!open) return null;

  return (
    <div className={styles.sheetRoot} role="presentation">
      <button
        type="button"
        className={styles.sheetBackdrop}
        aria-label="Close"
        onClick={onClose}
      />
      <div className={styles.sheetPanel} role="dialog" aria-modal="true">
        <div className={styles.sheetHandle} aria-hidden />
        {title ? <h2 className={styles.sheetTitle}>{title}</h2> : null}
        <div className={styles.sheetBody}>{children}</div>
      </div>
    </div>
  );
}
