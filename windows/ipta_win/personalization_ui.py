from __future__ import annotations
import tkinter as tk
from tkinter import ttk, messagebox
from . import personalization, paste


def open_window(parent, state):
    win=tk.Toplevel(parent);win.title('입타 개인화');win.geometry('540x650')
    notebook=ttk.Notebook(win);notebook.pack(fill='both',expand=True,padx=12,pady=12)
    words=ttk.Frame(notebook);tones=ttk.Frame(notebook);history=ttk.Frame(notebook)
    notebook.add(words,text='개인 사전');notebook.add(tones,text='앱별 말투·음성 편집');notebook.add(history,text='최근 받아쓰기')
    def attempt(action, refresh=lambda: None):
        try: action(); refresh()
        except (ValueError,OSError): messagebox.showerror('입타',state.personal.error or '입력값·중복 표현·저장 공간을 확인해 주세요.',parent=win)
    ttk.Label(words,text='등록한 표현만 한 번 바꿉니다. 최대 200개, 각 1~80자.',wraplength=480).pack(anchor='w',padx=8,pady=8)
    heard=tk.StringVar();spelling=tk.StringVar()
    ttk.Label(words,text='인식되는 표현').pack(anchor='w',padx=8)
    ttk.Entry(words,textvariable=heard).pack(fill='x',padx=8)
    ttk.Label(words,text='올바른 표기').pack(anchor='w',padx=8)
    ttk.Entry(words,textvariable=spelling).pack(fill='x',padx=8)
    word_list=tk.Listbox(words);word_list.pack(fill='both',expand=True,padx=8,pady=8)
    aliases=[]
    def refresh_words():
        aliases[:]=[v['heard'] for v in state.personal.data['vocabulary']]
        word_list.delete(0,'end')
        for v in state.personal.data['vocabulary']: word_list.insert('end',v['heard']+' → '+v['spelling'])
    ttk.Button(words,text='단어 등록',command=lambda: attempt(lambda:state.personal.add_word(heard.get(),spelling.get()),refresh_words)).pack(side='left',padx=8,pady=8)
    def delete_word():
        selected=word_list.curselection()
        if selected: attempt(lambda:state.personal.remove_word(aliases[selected[0]]),refresh_words)
    ttk.Button(words,text='선택 항목 삭제',command=delete_word).pack(side='left',padx=8)
    refresh_words()
    ttk.Label(tones,text='앱 실행 파일 이름으로 지정합니다. 예: cursor.exe\n다듬기를 켰을 때 녹음 시작 당시의 앱에 적용합니다.',wraplength=480).pack(anchor='w',padx=8,pady=8)
    app_name=tk.StringVar(value=state.target_app);tone=tk.StringVar(value='original')
    app_combo=ttk.Combobox(tones,textvariable=app_name);app_combo.pack(fill='x',padx=8)
    def refresh_apps(): app_combo.configure(values=sorted({paste.process_name(h) for h in paste._enum_visible()}-{''}))
    ttk.Button(tones,text='실행 중인 앱 목록',command=refresh_apps).pack(anchor='w',padx=8,pady=6)
    for key,label in personalization.TONES.items(): ttk.Radiobutton(tones,text=label,variable=tone,value=key).pack(anchor='w',padx=8)
    tone_list=tk.Listbox(tones,height=5);tone_list.pack(fill='x',padx=8,pady=8)
    def refresh_tones():
        tone_list.delete(0,'end')
        for app,value in state.personal.data['tones'].items(): tone_list.insert('end',app+' → '+personalization.TONES[value])
    ttk.Button(tones,text='말투 저장 (원래 말투는 규칙 삭제)',command=lambda: attempt(lambda:state.personal.set_tone(app_name.get(),tone.get()),refresh_tones)).pack(anchor='w',padx=8)
    refresh_tones()
    edit=tk.BooleanVar(value=state.selection_edit_enabled)
    def save_edit(): state.selection_edit_enabled=edit.get(); state.persist()
    ttk.Checkbutton(tones,text='선택한 글 음성 편집 사용',variable=edit,command=lambda:attempt(save_edit)).pack(anchor='w',padx=8,pady=8)
    ttk.Label(tones,text='글을 선택하고 단축키로 녹음한 뒤 “존댓말로”, “절반으로 줄여”, “영어로 바꿔”라고 말하세요. AI 연결이 필요합니다. 선택 글은 AI 제공자에게 전달됩니다. Windows UI Automation으로 선택을 읽을 수 있는 입력칸만 지원하며, 선택이나 입력칸이 바뀌면 자동으로 넣지 않습니다.',wraplength=480).pack(anchor='w',padx=8)
    enabled=tk.BooleanVar(value=state.personal.data['history_enabled'])
    def toggle_history():
        try: state.personal.set_history(enabled.get())
        finally: enabled.set(state.personal.data['history_enabled'])
        refresh_history()
    ttk.Checkbutton(history,text='최근 50개를 이 PC에 저장',variable=enabled,command=lambda:attempt(toggle_history)).pack(anchor='w',padx=8,pady=8)
    ttk.Label(history,text='원문과 결과만 저장합니다. 끄면 기록을 삭제합니다.\n사전·말투·기록은 %APPDATA%\\Ipta\\Personalization에 저장합니다.',wraplength=480).pack(anchor='w',padx=8)
    search=tk.StringVar();ttk.Entry(history,textvariable=search).pack(fill='x',padx=8,pady=8)
    history_list=tk.Listbox(history);history_list.pack(fill='both',expand=True,padx=8)
    ids=[]
    def refresh_history(*args):
        history_list.delete(0,'end');ids.clear()
        for r in state.personal.data['history']:
            if search.get().casefold() not in (r['raw']+' '+r['text']).casefold(): continue
            ids.append(r['id']);history_list.insert('end',r['date'][:16]+' '+r['text'][:75].replace('\n',' '))
    search.trace_add('write',refresh_history)
    def recover():
        selected=history_list.curselection()
        if selected and not state.recover_history(ids[selected[0]]): messagebox.showinfo('입타','녹음·처리가 끝난 뒤 복구하세요.',parent=win)
    ttk.Button(history,text='결과로 복구 (자동 입력 없음)',command=recover).pack(anchor='w',padx=8,pady=8)
    ttk.Button(history,text='새로고침',command=refresh_history).pack(side='left',padx=8,pady=8)
    ttk.Button(history,text='기록 전체 삭제',command=lambda:attempt(state.personal.clear_history,refresh_history)).pack(side='left',padx=8)
    refresh_history()
    if state.personal.error: ttk.Label(win,text=state.personal.error,foreground='#b00020',wraplength=500).pack(padx=12)
    return win
