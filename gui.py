import os
import sys
import shutil
import subprocess
import threading
import queue
from glob import glob

import customtkinter as ctk
from tkinter import filedialog

script_dir = os.path.dirname(os.path.abspath(__file__))

from recog import process_pdf_file, fill_template


class QueueHandler:
    def __init__(self, queue_):
        self.queue = queue_

    def write(self, text):
        stripped = text.strip()
        if stripped:
            self.queue.put(stripped)
        sys.__stdout__.write(text)

    def flush(self):
        sys.__stdout__.flush()


class App(ctk.CTk):
    def __init__(self):
        super().__init__()

        self.title("Конкурентная таблица")
        self.geometry("700x600")
        self.minsize(600, 500)

        self.folder_path = ctk.StringVar()
        self.pdf_vars = []
        self.pdf_files = []
        self.output_path = None
        self.log_queue = queue.Queue()

        self._build_ui()
        self._check_gs()

    def _build_ui(self):
        frame_top = ctk.CTkFrame(self)
        frame_top.pack(fill="x", padx=10, pady=(10, 5))

        ctk.CTkLabel(frame_top, text="Папка с PDF:").pack(side="left", padx=(5, 5))
        entry = ctk.CTkEntry(frame_top, textvariable=self.folder_path)
        entry.pack(side="left", fill="x", expand=True, padx=(0, 5))
        entry.bind("<KeyRelease>", lambda e: self._scan_folder())
        ctk.CTkButton(
            frame_top, text="Обзор...", command=self._select_folder, width=80
        ).pack(side="left")

        ctk.CTkLabel(self, text="Счета:", anchor="w").pack(fill="x", padx=10, pady=(10, 0))
        self.scroll_frame = ctk.CTkScrollableFrame(self)
        self.scroll_frame.pack(fill="both", expand=True, padx=10, pady=(2, 10))

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
        for w in self.scroll_frame.winfo_children():
            w.destroy()
        self.pdf_vars.clear()
        self.pdf_files.clear()
        self.btn_run.configure(state="disabled")
        self.btn_open.configure(state="disabled")
        self.output_path = None

        folder = self.folder_path.get()
        if not folder or not os.path.isdir(folder):
            return

        pdfs = sorted(glob(os.path.join(folder, "*.pdf")))
        if not pdfs:
            self._log("PDF не найдены")
            return

        self.pdf_files = pdfs
        self._log(f"Найдено PDF: {len(pdfs)}")

        for pdf in pdfs:
            var = ctk.IntVar(value=1)
            cb = ctk.CTkCheckBox(
                self.scroll_frame,
                text=os.path.basename(pdf),
                variable=var,
                onvalue=1,
                offvalue=0,
            )
            cb.pack(anchor="w", padx=5, pady=1)
            self.pdf_vars.append(var)

        self.btn_run.configure(state="normal")

    def _start_processing(self):
        selected = [f for f, v in zip(self.pdf_files, self.pdf_vars) if v.get()]
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
        sys.stdout = QueueHandler(self.log_queue)

        file_data_list = []
        try:
            for pdf_path in selected:
                process_pdf_file(pdf_path, file_data_list)

            if file_data_list:
                folder = self.folder_path.get()
                out = fill_template(file_data_list, folder, script_dir)
                self.log_queue.put(f"__DONE__{out}")
            else:
                self.log_queue.put("__DONE__")
        except Exception as e:
            self.log_queue.put(f"__DONE__Ошибка: {e}")
        finally:
            sys.stdout = sys.__stdout__

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
