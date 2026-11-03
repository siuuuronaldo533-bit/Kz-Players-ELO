
import os
import sqlite3
import telebot
from telebot.types import ReplyKeyboardMarkup, KeyboardButton, InlineKeyboardMarkup, InlineKeyboardButton

TOKEN = os.getenv9263532298:AAHMyi64AA6hk_K_cv9e5btjAax3X_2l5CQ
ADMIN_ID = int(os.getenv("ADMIN_ID", "0"))

bot = telebot.TeleBot9263532298:AAHMyi64AA6hk_K_cv9e5btjAax3X_2l5CQ

db = sqlite3.connect("league.db", check_same_thread=False)
cur = db.cursor()

cur.execute("""
CREATE TABLE IF NOT EXISTS players (
    user_id INTEGER PRIMARY KEY,
    name TEXT,
    rating INTEGER DEFAULT 1000,
    wins INTEGER DEFAULT 0,
    losses INTEGER DEFAULT 0
)
""")

cur.execute("""
CREATE TABLE IF NOT EXISTS matches (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    winner INTEGER,
    loser INTEGER,
    status TEXT DEFAULT 'pending'
)
""")
db.commit()


def menu():
    m = ReplyKeyboardMarkup(resize_keyboard=True)
    m.add(KeyboardButton("🎮 Матч жіберу"))
    m.add(KeyboardButton("🏆 Рейтинг"), KeyboardButton("👤 Профилім"))
    return m


@bot.message_handler(commands=["start"])
def start(message):
    user = message.from_user
    cur.execute(
        "INSERT OR IGNORE INTO players (user_id,name) VALUES (?,?)",
        (user.id, user.first_name)
    )
    db.commit()

    bot.send_message(
        message.chat.id,
        "⚽ KZ PLAYERS ELO LEAGUE\n\nҚош келдің!",
        reply_markup=menu()
    )


@bot.message_handler(func=lambda m: m.text == "🏆 Рейтинг")
def ranking(message):
    cur.execute(
        "SELECT name,rating,wins,losses FROM players ORDER BY rating DESC"
    )
    rows = cur.fetchall()

    text = "🏆 KZ PLAYERS RATING\n\n"
    for i, row in enumerate(rows, 1):
        text += f"{i}. {row[0]} — {row[1]} ELO | {row[2]}W/{row[3]}L\n"

    bot.send_message(message.chat.id, text)


@bot.message_handler(func=lambda m: m.text == "👤 Профилім")
def profile(message):
    cur.execute(
        "SELECT name,rating,wins,losses FROM players WHERE user_id=?",
        (message.from_user.id,)
    )
    p = cur.fetchone()

    if p:
        bot.send_message(
            message.chat.id,
            f"👤 {p[0]}\n🏆 ELO: {p[1]}\n"
            f"✅ Жеңіс: {p[2]}\n❌ Жеңіліс: {p[3]}"
        )


@bot.message_handler(func=lambda m: m.text == "🎮 Матч жіберу")
def match(message):
    msg = bot.send_message(
        message.chat.id,
        "Жеңімпаз ойыншының Telegram ID нөмірін жібер:"
    )
    bot.register_next_step_handler(msg, get_winner)


def get_winner(message):
    try:
        winner = int(message.text)
        msg = bot.send_message(
            message.chat.id,
            "Жеңілген ойыншының Telegram ID нөмірін жібер:"
        )
        bot.register_next_step_handler(msg, get_loser, winner)
    except ValueError:
        bot.send_message(message.chat.id, "ID сан болуы керек.")


def get_loser(message, winner):
    try:
        loser = int(message.text)

        if winner == loser:
            bot.send_message(message.chat.id, "Қате: екі ойыншы бірдей!")
            return

        for uid in (winner, loser):
            cur.execute(
                "INSERT OR IGNORE INTO players (user_id,name) VALUES (?,?)",
                (uid, str(uid))
            )

        cur.execute(
            "INSERT INTO matches (winner,loser) VALUES (?,?)",
            (winner, loser)
        )
        match_id = cur.lastrowid
        db.commit()

        markup = InlineKeyboardMarkup()
        markup.add(
            InlineKeyboardButton("✅ Растау", callback_data=f"yes_{match_id}"),
            InlineKeyboardButton("❌ Қабылдамау", callback_data=f"no_{match_id}")
        )

        bot.send_message(
            ADMIN_ID,
            f"⚽ Жаңа матч #{match_id}\n"
            f"Жеңімпаз ID: {winner}\nЖеңілген ID: {loser}",
            reply_markup=markup
        )

        bot.send_message(message.chat.id, "✅ Нәтиже әкімшіге жіберілді!")

    except ValueError:
        bot.send_message(message.chat.id, "ID дұрыс емес.")


@bot.callback_query_handler(func=lambda c: c.data.startswith(("yes_", "no_")))
def approve(call):
    if call.from_user.id != ADMIN_ID:
        bot.answer_callback_query(call.id, "Сен әкімші емессің!")
        return

    action, match_id = call.data.split("_")
    cur.execute(
        "SELECT winner,loser,status FROM matches WHERE id=?",
        (int(match_id),)
    )
    result = cur.fetchone()

    if not result or result[2] != "pending":
        bot.answer_callback_query(call.id, "Бұл матч бұрын қаралған.")
        return

    winner, loser, status = result

    if action == "yes":
        cur.execute(
            "UPDATE players SET rating=rating+20,wins=wins+1 WHERE user_id=?",
            (winner,)
        )
        cur.execute(
            "UPDATE players SET rating=MAX(0,rating-20),losses=losses+1 WHERE user_id=?",
            (loser,)
        )
        cur.execute(
            "UPDATE matches SET status='approved' WHERE id=?",
            (int(match_id),)
        )
        db.commit()
        bot.edit_message_text(
            "🏆 Матч расталды! Рейтинг жаңартылды.",
            call.message.chat.id,
            call.message.message_id
        )
    else:
        cur.execute(
            "UPDATE matches SET status='rejected' WHERE id=?",
            (int(match_id),)
        )
        db.commit()
        bot.edit_message_text(
            "❌ Матч қабылданбады.",
            call.message.chat.id,
            call.message.message_id
        )
