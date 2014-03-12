pgator
=============
[![Build Status](https://travis-ci.org/DSoftOut/pgator.png?branch=master)](https://travis-ci.org/DSoftOut/pgator)

Server that transforms JSON-RPC calls into SQL queries for PostgreSQL.

**Proposed by** [denizzzka](https://github.com/denizzzka)

[Technical documentation (ongoing)](http://dsoftout.github.io/pgator/app.html)

####Зачем это надо?
Чтобы работать с SQL БД необходим API.

Но SQL — это не API. SQL был разработан как интерфейс для конечных пользователей. (Да-да, для 1974 года это было отличное решение — миром правили текстовые терминалы!)

Так что, когда современные прикладные программисты используют SQL-интерфейс даже в виде возможности вызова лишь несложных запросов или хранимых процедур, то:
* Происходят ошибки при переносе запросов. Даже простой запрос можно написать неправильно (например, случайно не дописав часть условия WHERE в SELECT) - такую ошибку может быть трудно отловить. Кроме этого, некоторые ошибки являются результатом сознательного «улучшения» SQL-запроса прикладным программистом. Другими словами: поручать неSQL-программистам прикасаться к SQL-запросам в каком бы то ни было виде — плохая идея!
* Появляются проблемы с безопасностью. Клиентские и серверные библиотеки БД — небезопасны. Возможность передавать произвольный запрос в БД — потенциальная уязвимость, так как прежде чем запрос будет выполнен он проходит несколько сложных этапов, на каждом из которых в соответствующем коде может быть допущена ошибка, создающая уязвимость. (Ошибка из предыдущего примера также легко может привести к проблеме с безопасностью.)
* Проблемы с кэшированием. Чтобы организовать кэширование ответов БД придётся:
провести денормализацию внутри БД и в дальнейшем поддерживать такую её структуру; или
хранить кэш снаружи БД и передавать информацию об инвалидации кэша из БД с помощью флагов. И то, и другое больше смахивает на костыли и подпорки, чем на нормальную работу.

####Что же делать?
pgator предназначен для создания простого API к БД.
(В данный момент поддерживается только PostgreSQL.)

При его использовании SQL-программист описывает методы и их аргументы, а прикладной программист может использовать их без опасения создать проблемы на стороне RDBMS. При этом становится доступна возможность кэширования ответов БД.

####Зачем вы создали это, ведь существуют ORM?
ORM — это плохая концепция и дырявая абстракция, которая создаёт проблем больше, чем решает: в ORM нет реляционной алгебры, попытки использовать ORM с RDBMS приводят к тому, что схема БД расползается в строну прикладного кода. (http://en.wikipedia.org/wiki/Object-relational_impedance_mismatch)
