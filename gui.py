import os
import sys
import shutil
import subprocess
import threading
import queue
import re
from glob import glob

import tkinter as tk
import tkinter.ttk as ttk
import tkinterdnd2
from tkinterdnd2 import DND_FILES
from tkinter import filedialog

script_dir = getattr(sys, '_MEIPASS', os.path.dirname(os.path.abspath(__file__)))

from recog import process_pdf_file, fill_template


class ScrollableFrame(tk.Frame):
    def __init__(self, parent, **kwargs):
        super().__init__(parent, **kwargs)
        self.canvas = tk.Canvas(self, highlightthickness=0, borderwidth=0)
        self.scrollbar = ttk.Scrollbar(self, orient="vertical", command=self.canvas.yview)
        self.scrollable_frame = tk.Frame(self.canvas)

        self.scrollable_frame.bind(
            "<Configure>",
            lambda e: self.canvas.configure(scrollregion=self.canvas.bbox("all"))
        )
        self.canvas.create_window((0, 0), window=self.scrollable_frame, anchor="nw")
        self.canvas.configure(yscrollcommand=self.scrollbar.set)

        self.canvas.pack(side="left", fill="both", expand=True)
        self.scrollbar.pack(side="right", fill="y")

        self._bind_mousewheel(self.canvas)

    def _bind_mousewheel(self, widget):
        widget.bind("<MouseWheel>", self._on_mousewheel, add="+")
        for child in widget.winfo_children():
            self._bind_mousewheel(child)

    def _on_mousewheel(self, event):
        self.canvas.yview_scroll(int(-1 * (event.delta / 120)), "units")

    def destroy_children(self):
        for w in self.scrollable_frame.winfo_children():
            w.destroy()


class QueueHandler:
    def __init__(self, queue_):
        self.queue = queue_

    def write(self, text):
        stripped = text.strip()
        if stripped:
            self.queue.put(stripped)

    def flush(self):
        pass


class App(tk.Tk):
    def __init__(self):
        super().__init__()
        tkinterdnd2.TkinterDnD.require(self)

        style = ttk.Style()
        style.theme_use("clam")
        style.configure("TButton", padding=5)
        style.configure("TLabel", font=("Segoe UI", 10))
        style.configure("TCheckbutton", font=("Segoe UI", 10))
        style.configure("TNotebook.Tab", font=("Segoe UI", 10))

        self.title("Конкурентная таблица")
        self.geometry("700x650")
        self.minsize(600, 550)

        self.folder_path = tk.StringVar()
        self.pdf_files_folder = []
        self.pdf_vars_folder = []
        self.name_vars_folder = []

        self.pdf_files_dnd = []
        self.pdf_vars_dnd = []
        self.name_vars_dnd = []
        self.output_dir_var = tk.StringVar()
        self.output_name_var = tk.StringVar(value="конкурент.xlsx")

        self.request_item_rows = []
        self.output_path = None
        self.log_queue = queue.Queue()

        self._current_tab = "Выбор папки"

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

    @staticmethod
    def _setup_placeholder(entry, placeholder):
        entry._placeholder = placeholder
        entry.insert(0, placeholder)
        entry.config(fg="gray")
        def on_focus_in(e):
            if entry.get() == entry._placeholder:
                entry.delete(0, "end")
                entry.config(fg="black")
        def on_focus_out(e):
            if not entry.get():
                entry.insert(0, placeholder)
                entry.config(fg="gray")
        entry.bind("<FocusIn>", on_focus_in, add="+")
        entry.bind("<FocusOut>", on_focus_out, add="+")

    def _build_ui(self):
        top_frame = ttk.Frame(self)
        top_frame.pack(fill="x", padx=10, pady=(10, 0))
        ttk.Label(top_frame, text="Имя заявки:").pack(side="left", padx=(0, 5))
        self.request_name_var = tk.StringVar(value="Заявка")
        self.request_name_entry = tk.Entry(top_frame, textvariable=self.request_name_var)
        self.request_name_entry.pack(side="left", fill="x", expand=True)

        self.tabview = ttk.Notebook(self)
        self.tabview.pack(fill="both", expand=True, padx=10, pady=(10, 5))

        tab_folder = ttk.Frame(self.tabview)
        self.tabview.add(tab_folder, text="Выбор папки")
        self._build_folder_tab(tab_folder)

        tab_dnd = ttk.Frame(self.tabview)
        self.tabview.add(tab_dnd, text="Drag && Drop")
        self._build_dnd_tab(tab_dnd)

        tab_items = ttk.Frame(self.tabview)
        self.tabview.add(tab_items, text="Позиции заявки")
        self._build_request_items_tab(tab_items)

        self.tabview.bind("<<NotebookTabChanged>>", self._on_tab_switch)

        frame_btn = ttk.Frame(self)
        frame_btn.pack(fill="x", padx=10, pady=(0, 5))

        self.btn_run = ttk.Button(
            frame_btn, text="Запустить", command=self._start_processing
        )
        self.btn_run.pack(side="left", padx=5)
        self.btn_run.configure(state="disabled")

        self.btn_open = ttk.Button(
            frame_btn, text="Открыть результат", command=self._open_result
        )
        self.btn_open.pack(side="left", padx=5)
        self.btn_open.configure(state="disabled")

        ttk.Label(self, text="Лог:", anchor="w").pack(fill="x", padx=10, pady=(5, 0))
        log_frame = ttk.Frame(self)
        log_frame.pack(fill="x", padx=10, pady=(2, 10))
        self.log_box = tk.Text(log_frame, height=6)
        log_scroll = ttk.Scrollbar(log_frame, orient="vertical", command=self.log_box.yview)
        self.log_box.configure(yscrollcommand=log_scroll.set)
        self.log_box.pack(side="left", fill="both", expand=True)
        log_scroll.pack(side="right", fill="y")

        self.after(100, self._poll_log)

    def _build_folder_tab(self, parent):
        frame_top = ttk.Frame(parent)
        frame_top.pack(fill="x", padx=5, pady=(5, 5))

        ttk.Label(frame_top, text="Папка с PDF:").pack(side="left", padx=(5, 5))
        entry = tk.Entry(frame_top, textvariable=self.folder_path)
        entry.pack(side="left", fill="x", expand=True, padx=(0, 5))
        entry.bind("<KeyRelease>", lambda e: self._scan_folder())
        ttk.Button(
            frame_top, text="Обзор...", command=self._select_folder, width=10
        ).pack(side="left")

        ttk.Label(parent, text="Счета:", anchor="w").pack(fill="x", padx=5, pady=(10, 0))
        self.scroll_frame_folder = ScrollableFrame(parent)
        self.scroll_frame_folder.pack(fill="both", expand=True, padx=5, pady=(2, 5))

    def _build_dnd_tab(self, parent):
        self.drop_zone = tk.Frame(parent, highlightthickness=2, highlightbackground="gray")
        self.drop_zone.pack(fill="x", padx=5, pady=(10, 5), ipady=20)

        self.drop_label = ttk.Label(
            self.drop_zone, text="Перетащите PDF-файлы или папки сюда",
            font=("Segoe UI", 14),
        )
        self.drop_label.pack(expand=True, fill="both", padx=20, pady=20)

        self.drop_zone.drop_target_register(DND_FILES)
        self.drop_zone.dnd_bind('<<Drop>>', self._on_drop)

        ttk.Label(parent, text="Файлы:", anchor="w").pack(fill="x", padx=5, pady=(10, 0))
        self.scroll_frame_dnd = ScrollableFrame(parent)
        self.scroll_frame_dnd.pack(fill="both", expand=True, padx=5, pady=(2, 5))

        frame_settings = ttk.Frame(parent)
        frame_settings.pack(fill="x", padx=5, pady=(5, 5))

        ttk.Label(frame_settings, text="Имя файла:").grid(row=0, column=0, padx=(5, 5), pady=5, sticky="w")
        tk.Entry(frame_settings, textvariable=self.output_name_var).grid(row=0, column=1, padx=(0, 5), pady=5, sticky="ew")

        ttk.Label(frame_settings, text="Сохранить в:").grid(row=1, column=0, padx=(5, 5), pady=5, sticky="w")
        default_out = os.path.join(self._app_dir, "output")
        self.output_dir_var.set(default_out)
        entry_dir = tk.Entry(frame_settings, textvariable=self.output_dir_var)
        entry_dir.grid(row=1, column=1, padx=(0, 5), pady=5, sticky="ew")
        ttk.Button(frame_settings, text="Обзор...", command=self._select_output_dir, width=10).grid(
            row=1, column=2, padx=(0, 5), pady=5
        )

        frame_settings.columnconfigure(1, weight=1)

        btn_frame = ttk.Frame(parent)
        btn_frame.pack(fill="x", padx=5, pady=(0, 5))
        tk.Button(btn_frame, text="Очистить список", command=self._clear_dnd,
                  bg="gray", fg="white", relief="flat").pack(side="right")

    def _select_output_dir(self):
        folder = filedialog.askdirectory()
        if folder:
            self.output_dir_var.set(folder)

    def _clear_dnd(self):
        self.scroll_frame_dnd.destroy_children()
        self.pdf_files_dnd.clear()
        self.pdf_vars_dnd.clear()
        self.name_vars_dnd.clear()
        self._update_run_button()

    def _build_request_items_tab(self, parent):
        btn_frame = ttk.Frame(parent)
        btn_frame.pack(fill="x", padx=5, pady=(10, 5))
        ttk.Button(btn_frame, text="+ Добавить строку", command=self._add_request_item_row).pack(side="left", padx=5)
        tk.Button(btn_frame, text="Очистить", command=self._clear_request_items,
                  bg="gray", fg="white", relief="flat").pack(side="left", padx=5)

        self.scroll_frame_items = ScrollableFrame(parent)
        self.scroll_frame_items.pack(fill="both", expand=True, padx=5, pady=(2, 5))

    def _add_request_item_row(self, name="", qty=""):
        frame = ttk.Frame(self.scroll_frame_items.scrollable_frame)
        frame.pack(fill="x", padx=5, pady=1)

        name_var = tk.StringVar(value=name)
        qty_var = tk.StringVar(value=qty)

        ttk.Label(frame, text="Название:", width=10).pack(side="left", padx=(5, 2))
        tk.Entry(frame, textvariable=name_var).pack(side="left", fill="x", expand=True, padx=(0, 5))

        ttk.Label(frame, text="Кол-во:", width=7).pack(side="left", padx=(0, 2))
        tk.Entry(frame, textvariable=qty_var, width=10).pack(side="left", padx=(0, 5))

        tk.Button(frame, text="×", width=3, bg="red", fg="white", relief="flat",
                   command=lambda f=frame: self._remove_request_item_row(f)).pack(side="left", padx=(0, 5))

        self.request_item_rows.append({"frame": frame, "name_var": name_var, "qty_var": qty_var})

    def _remove_request_item_row(self, frame):
        frame.destroy()
        self.request_item_rows[:] = [r for r in self.request_item_rows if r["frame"] != frame]

    def _clear_request_items(self):
        for r in self.request_item_rows:
            r["frame"].destroy()
        self.request_item_rows.clear()

    def _add_file_row_dnd(self, file_path):
        row_frame = ttk.Frame(self.scroll_frame_dnd.scrollable_frame)
        row_frame.pack(fill="x", padx=5, pady=1)

        var = tk.IntVar(value=1)
        cb = ttk.Checkbutton(
            row_frame,
            text=os.path.basename(file_path),
            variable=var,
        )
        cb.pack(side="left", padx=(5, 5))

        name_var = tk.StringVar()
        entry = tk.Entry(row_frame, textvariable=name_var)
        entry.pack(side="left", fill="x", expand=True, padx=(0, 5))
        self._setup_placeholder(entry, os.path.basename(file_path))

        self.pdf_files_dnd.append(file_path)
        self.pdf_vars_dnd.append(var)
        self.name_vars_dnd.append(name_var)

    def _on_drop(self, event):
        paths = self._parse_drop_data(event.data)
        added = 0
        for path in paths:
            if os.path.isfile(path) and path.lower().endswith('.pdf'):
                if path not in self.pdf_files_dnd:
                    self._add_file_row_dnd(path)
                    added += 1
            elif os.path.isdir(path):
                pdfs = sorted(glob(os.path.join(path, "**", "*.[pP][dD][fF]"), recursive=True))
                for pdf in pdfs:
                    if pdf not in self.pdf_files_dnd:
                        self._add_file_row_dnd(pdf)
                        added += 1
        if added:
            self._log(f"Добавлено PDF: {added}")
            self._update_run_button()

    def _on_tab_switch(self, event=None):
        idx = self.tabview.index("current")
        self._current_tab = self.tabview.tab(idx, "text")
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
        self.scroll_frame_folder.destroy_children()
        self.pdf_files_folder.clear()
        self.pdf_vars_folder.clear()
        self.name_vars_folder.clear()

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
            row_frame = ttk.Frame(self.scroll_frame_folder.scrollable_frame)
            row_frame.pack(fill="x", padx=5, pady=1)

            var = tk.IntVar(value=1)
            cb = ttk.Checkbutton(
                row_frame,
                text=os.path.basename(pdf),
                variable=var,
            )
            cb.pack(side="left", padx=(5, 5))

            name_var = tk.StringVar()
            entry = tk.Entry(row_frame, textvariable=name_var)
            entry.pack(side="left", fill="x", expand=True, padx=(0, 5))
            self._setup_placeholder(entry, os.path.basename(pdf))

            self.pdf_vars_folder.append(var)
            self.name_vars_folder.append(name_var)

        self._update_run_button()

    def _update_run_button(self):
        current_tab = self._current_tab
        if current_tab == "Выбор папки":
            state = "normal" if self.pdf_files_folder else "disabled"
        elif current_tab == "Позиции заявки":
            state = "normal" if self.request_item_rows else "disabled"
        else:
            state = "normal" if self.pdf_files_dnd else "disabled"
        self.btn_run.configure(state=state)

    def _collect_selected(self, files, vars, name_vars):
        selected = []
        block_names = {}
        for f, v, nv in zip(files, vars, name_vars):
            if v.get():
                selected.append(f)
                custom = nv.get().strip()
                if custom:
                    block_names[os.path.basename(f)] = custom
        return selected, block_names

    def _start_processing(self):
        current_tab = self._current_tab
        selected = []
        block_names = {}
        if current_tab == "Выбор папки":
            selected, block_names = self._collect_selected(
                self.pdf_files_folder, self.pdf_vars_folder, self.name_vars_folder)
        elif current_tab == "Позиции заявки":
            selected, block_names = self._collect_selected(
                self.pdf_files_folder, self.pdf_vars_folder, self.name_vars_folder)
            if not selected:
                selected, block_names = self._collect_selected(
                    self.pdf_files_dnd, self.pdf_vars_dnd, self.name_vars_dnd)
        else:
            selected, block_names = self._collect_selected(
                self.pdf_files_dnd, self.pdf_vars_dnd, self.name_vars_dnd)

        if not selected:
            self._log("Нет выбранных файлов")
            return

        request_name = self.request_name_var.get().strip() or "Заявка"

        request_items = None
        if self.request_item_rows:
            items = [(r["name_var"].get().strip(), r["qty_var"].get().strip())
                     for r in self.request_item_rows if r["name_var"].get().strip()]
            if items:
                request_items = items

        self.btn_run.configure(state="disabled")
        self.btn_open.configure(state="disabled")
        self.output_path = None
        self.log_box.delete("1.0", "end")

        thread = threading.Thread(
            target=self._run_processing, args=(selected, block_names, request_name, request_items), daemon=True
        )
        thread.start()

    def _run_processing(self, selected, block_names, request_name, request_items):
        old_stdout = sys.stdout
        sys.stdout = QueueHandler(self.log_queue)

        file_data_list = []
        try:
            for pdf_path in selected:
                process_pdf_file(pdf_path, file_data_list)

            if file_data_list:
                current_tab = self._current_tab
                if current_tab == "Выбор папки":
                    folder = self.folder_path.get()
                    out = fill_template(file_data_list, folder, script_dir,
                                        block_names=block_names,
                                        request_name=request_name,
                                        request_items=request_items)
                else:
                    out_dir = self.output_dir_var.get()
                    out_name = self.output_name_var.get()
                    os.makedirs(out_dir, exist_ok=True)
                    out = fill_template(
                        file_data_list, "", script_dir,
                        output_path=os.path.join(out_dir, out_name),
                        block_names=block_names,
                        request_name=request_name,
                        request_items=request_items,
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
