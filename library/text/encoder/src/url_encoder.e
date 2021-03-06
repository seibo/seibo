note
	description: "Summary description for {URL_ENCODER}."
	legal: "See notice at end of class."
	status: "See notice at end of class."
	date: "$Date$"
	revision: "$Revision$"

class
	URL_ENCODER

inherit
	ENCODER [STRING_32, STRING_8]

	PLATFORM
		export
			{NONE} all
		end

feature -- Access

	name: STRING = "URL-encoded"

feature -- Status report

	has_error: BOOLEAN

feature -- Encoder

	encoded_string (s: STRING_32): STRING_8
			-- URL-encoded value of `s'.
		local
			i, n: INTEGER
			uc: CHARACTER_32
			c: CHARACTER_8
		do
			has_error := False
			create Result.make (s.count + s.count // 10)
			n := s.count
			from i := 1 until i > n loop
				uc := s.item (i)
				if uc.is_character_8 then
					c := uc.to_character_8
					inspect c
					when
						'A' .. 'Z',
						'a' .. 'z', '0' .. '9',
						'.', '-', '~', '_'
					 then
						 Result.extend (c)
					when ' ' then
						Result.extend ('+')
					else
						Result.append (url_encoded_char (uc))
					end
				else
					Result.append (url_encoded_char (uc))
				end
				i := i + 1
			end
		end

feature {NONE} -- encoder character

	url_encoded_char (uc: CHARACTER_32): STRING_8
		do
			create Result.make (3)
			if uc.is_character_8 then
				Result.extend ('%%')
				Result.append (uc.code.to_hex_string)
				from
				until
					Result.count < 2 or else Result[2] /= '0'
				loop
					Result.remove (2)
				end
			else
				has_error := True --| Non-ascii escape not currently supported
			end
		ensure
			exists: Result /= Void
		end

feature -- Decoder

	decoded_string (v: STRING_8): STRING_32
			-- The URL-encoded equivalent of the given string
		local
			i, n: INTEGER
			c: CHARACTER
			pr: CELL [INTEGER]
		do
			n := v.count
			create Result.make (n)
			from i := 1
			until i > n
			loop
				c := v.item (i)
				inspect c
				when '+' then
					Result.append_character ({CHARACTER_32}' ')
				when '%%' then
					-- An escaped character ?
					if i = n then
						Result.append_character (c.to_character_32)
					else
						create pr.put (i)
						Result.append (url_decoded_char (v, pr))
						i := pr.item
					end
				else
					Result.append_character (c.to_character_32)
				end
				i := i + 1
			end
		end

feature {NONE} -- decoded character

	url_decoded_char (buf: STRING_8; posr: CELL [INTEGER]): STRING_32
			-- Character(s) resulting from decoding the URL-encoded string
		require
			stream_exists: buf /= Void
			posr_exists: posr /= Void
			valid_start: posr.item <= buf.count
		local
			c: CHARACTER
			i, n, nb: INTEGER
			not_a_digit: BOOLEAN
			ascii_pos, ival: INTEGER
			pos: INTEGER
		do
				--| pos is index in stream of escape character ('%')
			pos := posr.item
			create Result.make (4)
			if buf.item (pos + 1) = 'u' then
				-- An escaped Unicode (ucs2) value, from ECMA scripts
				-- Has the form: %u<n> where <n> is the UCS value
				-- of the character (two byte integer, one to 4 chars
				-- after escape sequence).
				-- UTF-8 result can be 1 to 4 characters
				n := buf.count
				from i := pos + 2
				until (i > n) or not_a_digit
				loop
					c := buf.item (i)
					if c.is_hexa_digit then
						ival := ival * 16
						if c.is_digit then
							ival := ival + (c |-| '0')
						else
							ival := ival + (c.upper |-| 'A') + 10
						end
						i := i + 1
					else
						not_a_digit := True
					end
				end
				posr.replace (i)
				-- ival is now UCS2 value; needs conversion to UTF8
				Result.append_code (ival.as_natural_32)
				nb := utf8_bytes_in_sequence (buf, pos)
			else
				-- ASCII char?
				ascii_pos := hex_to_integer_32 (buf.substring (pos+1, pos+2))
				if ascii_pos >= 0x80 and ascii_pos <= 0xff then
					-- Might be improperly escaped
					Result.append_code (ascii_pos.as_natural_32)
					posr.replace (pos + 2)
				else
					Result.append_code (ascii_pos.as_natural_32)
					posr.replace (pos + 2)
				end
			end
		ensure
			exists: Result /= Void
		end

feature {NONE} -- UTF8

	utf8_bytes_in_sequence (s: STRING_8; spos: INTEGER): INTEGER
			--	If the given character is a legal first byte element in a
			-- utf8 byte sequence (aka character), then return the number
			-- of bytes in that sequence
			--	Result of zero means it's not a utf8 first byte
		require
			exists: s /= Void
			long_enough: s.count >= spos
		do
			Result := bytes_in_utf8_char (s.item (spos))
		end

	bytes_in_utf8_char (v: CHARACTER_8): INTEGER
			--	If the given byte a legal first byte element in a utf8 sequence,
			--	then the number of bytes in that character
			--	Zero denotes an error, i.e. not a legal UTF8 char
			--
			-- The first byte of a UTF8 encodes the length
		local
			c: NATURAL_8
		do
			c := v.code.to_natural_8
			Result := 1 -- 7 bit ASCII
			if (c & 0x80) /= 0 then
				-- Hi bit means not ASCII
				Result := 0
				if (c & 0xe0) = 0xc0 then
					-- If we see a first byte as b110xxxxx
					-- then we expect a two-byte character
					Result := 2
				elseif (c & 0xf0) = 0xe0 then
					-- If we see a first byte as b1110xxxx
					-- then we expect a three-byte character
					Result := 3
				elseif (c & 0xf8) = 0xf0 then
					-- If we see a first byte as b11110xxx
					-- then we expect a four-byte character
					Result := 4
				elseif (c & 0xfc) = 0xf8 then
					-- If we see a first byte as b111110xx
					-- then we expect a five-byte character
					Result := 5
				elseif (c & 0xfe) = 0xfc then
					-- If we see a first byte as b1111110x
					-- then we expect a six-byte character
					Result := 6
				end
			end
		end

feature {NONE} -- Hexadecimal and strings

	hex_to_integer_32 (s: STRING): INTEGER_32
			-- Hexadecimal string `s' converted to INTEGER_32 value
		require
			s_not_void: s /= Void
		local
			i, nb: INTEGER;
			char: CHARACTER
		do
			nb := s.count

			if nb >= 2 and then s.item (2) = 'x' then
				i := 3
			else
				i := 1
			end

			from
			until
				i > nb
			loop
				Result := Result * 16
				char := s.item (i)
				if char >= '0' and then char <= '9' then
					Result := Result + (char |-| '0')
				else
					Result := Result + (char.lower |-| 'a' + 10)
				end
				i := i + 1
			end
		end

	hex_to_integer_64 (s: STRING): INTEGER_64
			-- Hexadecimal string `s' converted to INTEGER_64 value
		require
			s_not_void: s /= Void
		local
			i, nb: INTEGER;
			char: CHARACTER
		do
			nb := s.count

			if nb >= 2 and then s.item (2) = 'x' then
				i := 3
			else
				i := 1
			end

			from
			until
				i > nb
			loop
				Result := Result * 16
				char := s.item (i)
				if char >= '0' and then char <= '9' then
					Result := Result + (char |-| '0')
				else
					Result := Result + (char.lower |-| 'a' + 10)
				end
				i := i + 1
			end
		end

	hex_to_pointer (s: STRING): POINTER
			-- Hexadecimal string `s' converted to POINTER value
		require
			s_not_void: s /= Void
		local
			val_32: INTEGER_32
			val_64: INTEGER_64
		do
			if Pointer_bytes = Integer_64_bytes then
				val_64 := hex_to_integer_64 (s)
				($Result).memory_copy ($val_64, Pointer_bytes)
			else
				val_32 := hex_to_integer_32 (s)
				($Result).memory_copy ($val_32, Pointer_bytes)
			end
		end

note
	copyright: "Copyright (c) 1984-2011, Eiffel Software and others"
	license: "Eiffel Forum License v2 (see http://www.eiffel.com/licensing/forum.txt)"
	source: "[
			Eiffel Software
			5949 Hollister Ave., Goleta, CA 93117 USA
			Telephone 805-685-1006, Fax 805-685-6869
			Website http://www.eiffel.com
			Customer support http://support.eiffel.com
		]"
end
