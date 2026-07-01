import os
import sys
import shutil
import subprocess
import threading
import queue
import re
from glob import glob

import customtkinter as ctk
import tkinterdnd2
from tkinterdnd2 import DND_FILES
from tkinter import filedialog

script_dir = getattr(sys, '_MEIPASS', os.path.dirname(os.path.abspath(__file__)))

from recog import process_pdf_file, fill_template


class QueueHandler:
    def __init__(self, queue_):
        self.queue = queue_

    def write(self, text):
        stripped = text.strip()
        if stripped:
            self.queue.put(stripped)

    def flush(self):
        pass


class App(tkinterdnd2.Tk):
    def __init__(self):
        super().__init__()

        self.title("Конкурентная таблица")
        self.geometry("700x650")
        self.minsize(600, 550)

        self.folder_path = ctk.StringVar()
        self.pdf_files_folder = []
        self.pdf_vars_folder = []

        self.pdf_files_dnd = []
        self.pdf_vars_dnd = []
        self.output_dir_var = ctk.StringVar()
        self.output_name_var = ctk.StringVar(value="конкурент.xlsx")

        self.output_path = None
        self.log_queue = queue.Queue()

        self._build_ui()
        self._check_gs()

    @property
    def _app_dir(self):
        if getattr(sys, 'frozen', False):
            return os.path.dirname(sys.executable)
        return os.path.dirname(os.path.abspath(__file__))

    @staticmethod
    def _parse_drop_data(data):
        paths = []
        for p in re.findall(r'\{([^}]+)\}|\S+', data):
            if p:
                p = p.replace('file:///', '', 1).replace('file://', '', 1)
                paths.append(p)
        return paths

    def _build_ui(self):
        self.tabview = ctk.CTkTabview(self, command=self._on_tab_switch)
        self.tabview.pack(fill="both", expand=True, padx=10, pady=(10, 5))

        tab_folder = self.tabview.add("Выбор папки")
        self._build_folder_tab(tab_folder)

        tab_dnd = self.tabview.add("Drag && Drop")
        self._build_dnd_tab(tab_dnd)

        frame_btn = ctk.CTkFrame(self)
        frame_btn.pack(fill="x", padx=10, pady=(0, 5))

        self.btn_run = ctk.CTkButton(
            frame_btn, text="Запустить", command=self._start_processing
        )
        self.btn_run.pack(side="left", padx=5)
        self.btn_run.configure(state="disabled")

        self.btn_open = ctk.CTkButton(
            frame_btn, text="Открыть результат", command=self._open_result
        )
        self.btn_open.pack(side="left", padx=5)
        self.btn_open.configure(state="disabled")

        ctk.CTkLabel(self, text="Лог:", anchor="w").pack(fill="x", padx=10, pady=(5, 0))
        self.log_box = ctk.CTkTextbox(self, height=120, state="normal")
        self.log_box.pack(fill="x", padx=10, pady=(2, 10))

        self.after(100, self._poll_log)

    def _build_folder_tab(self, parent):
        frame_top = ctk.CTkFrame(parent)
        frame_top.pack(fill="x", padx=5, pady=(5, 5))

        ctk.CTkLabel(frame_top, text="Папка с PDF:").pack(side="left", padx=(5, 5))
        entry = ctk.CTkEntry(frame_top, textvariable=self.folder_path)
        entry.pack(side="left", fill="x", expand=True, padx=(0, 5))
        entry.bind("<KeyRelease>", lambda e: self._scan_folder())
        ctk.CTkButton(
            frame_top, text="Обзор...", command=self._select_folder, width=80
        ).pack(side="left")

        ctk.CTkLabel(parent, text="Счета:", anchor="w").pack(fill="x", padx=5, pady=(10, 0))
        self.scroll_frame_folder = ctk.CTkScrollableFrame(parent)
        self.scroll_frame_folder.pack(fill="both", expand=True, padx=5, pady=(2, 5))

    def _build_dnd_tab(self, parent):
        self.drop_zone = ctk.CTkFrame(parent, border_width=2, border_color="gray")
        self.drop_zone.pack(fill="x", padx=5, pady=(10, 5), ipady=20)

        self.drop_label = ctk.CTkLabel(
            self.drop_zone, text="Перетащите PDF-файлы или папки сюда",
            font=ctk.CTkFont(size=14),
        )
        self.drop_label.pack(expand=True, fill="both", padx=20, pady=20)

        self.drop_zone.drop_target_register(DND_FILES)
        self.drop_zone.dnd_bind('<<Drop>>', self._on_drop)

        ctk.CTkLabel(parent, text="Файлы:", anchor="w").pack(fill="x", padx=5, pady=(10, 0))
        self.scroll_frame_dnd = ctk.CTkScrollableFrame(parent)
        self.scroll_frame_dnd.pack(fill="both", expand=True, padx=5, pady=(2, 5))

        frame_settings = ctk.CTkFrame(parent)
        frame_settings.pack(fill="x", padx=5, pady=(5, 5))

        ctk.CTkLabel(frame_settings, text="Имя файла:").grid(row=0, column=0, padx=(5, 5), pady=5, sticky="w")
        ctk.CTkEntry(frame_settings, textvariable=self.output_name_var).grid(row=0, column=1, padx=(0, 5), pady=5, sticky="ew")

        ctk.CTkLabel(frame_settings, text="Сохранить в:").grid(row=1, column=0, padx=(5, 5), pady=5, sticky="w")
        default_out = os.path.join(self._app_dir, "output")
        self.output_dir_var.set(default_out)
        entry_dir = ctk.CTkEntry(frame_settings, textvariable=self.output_dir_var)
        entry_dir.grid(row=1, column=1, padx=(0, 5), pady=5, sticky="ew")
        ctk.CTkButton(frame_settings, text="Обзор...", command=self._select_output_dir, width=80).grid(
            row=1, column=2, padx=(0, 5), pady=5
        )

        frame_settings.columnconfigure(1, weight=1)

        btn_frame = ctk.CTkFrame(parent, fg_color="transparent")
        btn_frame.pack(fill="x", padx=5, pady=(0, 5))
        ctk.CTkButton(btn_frame, text="Очистить список", command=self._clear_dnd, fg_color="gray").pack(side="right")

    def _select_output_dir(self):
        folder = filedialog.askdirectory()
        if folder:
            self.output_dir_var.set(folder)

    def _clear_dnd(self):
        for w in self.scroll_frame_dnd.winfo_children():
            w.destroy()
        self.pdf_files_dnd.clear()
        self.pdf_vars_dnd.clear()
        self._update_run_button()

    def _on_drop(self, event):
        paths = self._parse_drop_data(event.data)
        added = 0
        for path in paths:
            if os.path.isfile(path) and path.lower().endswith('.pdf'):
                if path not in self.pdf_files_dnd:
                    self.pdf_files_dnd.append(path)
                    var = ctk.IntVar(value=1)
                    cb = ctk.CTkCheckBox(
                        self.scroll_frame_dnd,
                        text=os.path.basename(path),
                        variable=var,
                        onvalue=1,
                        offvalue=0,
                    )
                    cb.pack(anchor="w", padx=5, pady=1)
                    self.pdf_vars_dnd.append(var)
                    added += 1
            elif os.path.isdir(path):
                pdfs = sorted(glob(os.path.join(path, "**", "*.[pP][dD][fF]"), recursive=True))
                for pdf in pdfs:
                    if pdf not in self.pdf_files_dnd:
                        self.pdf_files_dnd.append(pdf)
                        var = ctk.IntVar(value=1)
                        cb = ctk.CTkCheckBox(
                            self.scroll_frame_dnd,
                            text=os.path.basename(pdf),
                            variable=var,
                            onvalue=1,
                            offvalue=0,
                        )
                        cb.pack(anchor="w", padx=5, pady=1)
                        self.pdf_vars_dnd.append(var)
                        added += 1
        if added:
            self._log(f"Добавлено PDF: {added}")
            self._update_run_button()

    def _on_tab_switch(self):
        self._update_run_button()

    def _check_gs(self):
        gs_cmd = "gswin64c" if sys.platform == "win32" else "gs"
        if not shutil.which(gs_cmd):
            self._log(
                "⚠ Ghostscript не найден. Установите с ghostscript.com "
                "и перезапустите программу."
            )

    def _select_folder(self):
        folder = filedialog.askdirectory()
        if folder:
            self.folder_path.set(folder)
            self._scan_folder()

    def _scan_folder(self):
        for w in self.scroll_frame_folder.winfo_children():
            w.destroy()
        self.pdf_files_folder.clear()
        self.pdf_vars_folder.clear()

        folder = self.folder_path.get()
        if not folder or not os.path.isdir(folder):
            self._update_run_button()
            return

        pdfs = sorted(glob(os.path.join(folder, "*.[pP][dD][fF]")))
        if not pdfs:
            self._log("PDF не найдены")
            self._update_run_button()
            return

        self.pdf_files_folder = pdfs
        self._log(f"Найдено PDF: {len(pdfs)}")

        for pdf in pdfs:
            var = ctk.IntVar(value=1)
            cb = ctk.CTkCheckBox(
                self.scroll_frame_folder,
                text=os.path.basename(pdf),
                variable=var,
                onvalue=1,
                offvalue=0,
            )
            cb.pack(anchor="w", padx=5, pady=1)
            self.pdf_vars_folder.append(var)

        self._update_run_button()

    def _update_run_button(self):
        current_tab = self.tabview.get()
        if current_tab == "Выбор папки":
            state = "normal" if self.pdf_files_folder else "disabled"
        else:
            state = "normal" if self.pdf_files_dnd else "disabled"
        self.btn_run.configure(state=state)

    def _start_processing(self):
        current_tab = self.tabview.get()
        if current_tab == "Выбор папки":
            selected = [f for f, v in zip(self.pdf_files_folder, self.pdf_vars_folder) if v.get()]
        else:
            selected = [f for f, v in zip(self.pdf_files_dnd, self.pdf_vars_dnd) if v.get()]

        if not selected:
            self._log("Нет выбранных файлов")
            return

        self.btn_run.configure(state="disabled")
        self.btn_open.configure(state="disabled")
        self.output_path = None
        self.log_box.delete("0.0", "end")

        thread = threading.Thread(
            target=self._run_processing, args=(selected,), daemon=True
        )
        thread.start()

    def _run_processing(self, selected):
        old_stdout = sys.stdout
        sys.stdout = QueueHandler(self.log_queue)

        file_data_list = []
        try:
            for pdf_path in selected:
                process_pdf_file(pdf_path, file_data_list)

            if file_data_list:
                current_tab = self.tabview.get()
                if current_tab == "Выбор папки":
                    folder = self.folder_path.get()
                    out = fill_template(file_data_list, folder, script_dir)
                else:
                    out_dir = self.output_dir_var.get()
                    out_name = self.output_name_var.get()
                    os.makedirs(out_dir, exist_ok=True)
                    out = fill_template(
                        file_data_list, "", script_dir,
                        output_path=os.path.join(out_dir, out_name),
                    )
                self.log_queue.put(f"__DONE__{out}")
            else:
                self.log_queue.put("__DONE__")
        except Exception as e:
            self.log_queue.put(f"__DONE__Ошибка: {e}")
        finally:
            sys.stdout = old_stdout

    def _poll_log(self):
        try:
            while True:
                msg = self.log_queue.get_nowait()
                if msg.startswith("__DONE__"):
                    rest = msg[len("__DONE__"):]
                    if rest.startswith("Ошибка"):
                        self._log(rest)
                        self._log("")
                    elif rest:
                        self.output_path = rest
                        self._log("Готово!")
                    self._processing_done()
                else:
                    self._log(msg)
        except queue.Empty:
            pass
        self.after(100, self._poll_log)

    def _log(self, text):
        self.log_box.insert("end", text + "\n")
        self.log_box.see("end")

    def _processing_done(self):
        self.btn_run.configure(state="normal")
        if self.output_path and os.path.exists(self.output_path):
            self.btn_open.configure(state="normal")

    def _open_result(self):
        if not self.output_path or not os.path.exists(self.output_path):
            return
        p = self.output_path
        if sys.platform == "win32":
            os.startfile(p)
        elif sys.platform == "darwin":
            subprocess.run(["open", p])
        else:
            subprocess.run(["xdg-open", p])


if __name__ == "__main__":
    App().mainloop()
